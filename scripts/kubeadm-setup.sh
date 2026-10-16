#!/bin/bash
set -euo pipefail

# Bring up a kubeadm cluster with Cilium on the VMs listed in machines.txt.
#
# Usage (from the folder that has machines.txt):
#   ./kubeadm-setup.sh

SCRIPT_DIRECTORY=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(cd -- "${SCRIPT_DIRECTORY}/.." && pwd)
# shellcheck disable=SC1091
source "${REPOSITORY_ROOT}/versions.env"

K8S_VERSION=${KUBERNETES_MINOR}
POD_CIDR=10.244.0.0/16

# Fail early, before touching the VMs
[ -f machines.txt ] || { echo "machines.txt not found. Create the VM inventory first." >&2; exit 1; }
command -v helm > /dev/null || { echo "helm is not installed: https://helm.sh/docs/intro/install/" >&2; exit 1; }

SERVER_IP=$(awk '$3 == "server" {print $1}' machines.txt)
WORKER_IPS=$(awk '$3 != "server" {print $1}' machines.txt)
ALL_IPS=$(cut -d " " -f 1 machines.txt)
[ -n "$SERVER_IP" ] || { echo "No 'server' line in machines.txt" >&2; exit 1; }

# 1. Passwordless sudo on each VM, so the rest can run over ssh without prompts.
#    Asks for your VM password once per VM, only the first time.
for IP in $ALL_IPS; do
    if ! ssh -n ${IP} sudo -n true 2> /dev/null; then
        echo "== ${IP}: enabling passwordless sudo (enter your VM password)"
        ssh -t ${IP} 'echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/90-k8s-lab > /dev/null && sudo chmod 440 /etc/sudoers.d/90-k8s-lab && sudo visudo -cf /etc/sudoers.d/90-k8s-lab'
    fi
done

# 2. Prepare every node: swap off, kernel settings, containerd, kubeadm/kubelet/kubectl
NODE_PREP=$(mktemp)
trap 'rm -f "$NODE_PREP"' EXIT
cat << EOF > "$NODE_PREP"
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a

# Kubernetes needs swap off
swapoff -a
sed -i '/\sswap\s/s/^/#/' /etc/fstab

# Kernel modules and settings for container networking
printf 'overlay\nbr_netfilter\n' > /etc/modules-load.d/k8s.conf
modprobe overlay
modprobe br_netfilter
printf 'net.bridge.bridge-nf-call-iptables = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\nnet.ipv4.ip_forward = 1\n' > /etc/sysctl.d/k8s.conf
sysctl --system > /dev/null

# containerd, using the systemd cgroup driver the kubelet expects
apt-get update -q
apt-get install -y -q containerd curl gpg
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
grep -q 'SystemdCgroup = true' /etc/containerd/config.toml || { echo "Could not set SystemdCgroup" >&2; exit 1; }
systemctl restart containerd

# kubeadm, kubelet and kubectl from the official repo
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key |
    gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /' \
    > /etc/apt/sources.list.d/kubernetes.list
apt-get update -q
apt-get install -y -q kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet
EOF

for IP in $ALL_IPS; do
    echo "== ${IP}: preparing node"
    scp -q "$NODE_PREP" ${IP}:k8s-node-prep.sh
    ssh -n ${IP} "sudo bash k8s-node-prep.sh && rm k8s-node-prep.sh"
done

# 3. Create the control plane on server (skipped if it already exists).
#    kube-proxy is left out because Cilium replaces it.
if ssh -n ${SERVER_IP} test -f /etc/kubernetes/admin.conf; then
    echo "== ${SERVER_IP}: control plane already initialised, skipping kubeadm init"
else
    echo "== ${SERVER_IP}: kubeadm init"
    ssh -n ${SERVER_IP} sudo kubeadm init \
        --apiserver-advertise-address=${SERVER_IP} \
        --pod-network-cidr=${POD_CIDR} \
        --skip-phases=addon/kube-proxy
fi

# 4. kubectl access from this machine. admin.conf is cluster-admin: never commit it.
mkdir -p -m 700 ~/.kube
if [ -f ~/.kube/config ]; then
    cp ~/.kube/config ~/.kube/config.bak.$(date +%Y%m%d%H%M%S)
fi
ssh -n ${SERVER_IP} "sudo cat /etc/kubernetes/admin.conf" > ~/.kube/config
chmod 600 ~/.kube/config

# 5. Cilium as the CNI and kube-proxy replacement
helm repo add cilium https://helm.cilium.io > /dev/null 2>&1 || true
helm repo update cilium > /dev/null
helm upgrade --install cilium cilium/cilium --version ${CILIUM_VERSION} \
    --namespace kube-system \
    --set kubeProxyReplacement=true \
    --set k8sServiceHost=${SERVER_IP} \
    --set k8sServicePort=6443 \
    --set ipam.mode=kubernetes

# 6. Join the workers (skipped if already joined)
JOIN_CMD=$(ssh -n ${SERVER_IP} sudo kubeadm token create --print-join-command)
for IP in $WORKER_IPS; do
    if ssh -n ${IP} test -f /etc/kubernetes/kubelet.conf; then
        echo "== ${IP}: already joined, skipping"
    else
        echo "== ${IP}: joining cluster"
        ssh -n ${IP} "sudo ${JOIN_CMD}"
    fi
done

# 7. Wait for everything to be Ready
echo "== Waiting for nodes to be Ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=10m
kubectl get nodes -o wide
