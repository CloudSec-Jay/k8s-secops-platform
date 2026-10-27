# kubeadm Hybrid Cluster

This runbook bootstraps the lab's Kubernetes cluster: a Hyper-V virtual machine as the control plane and two bare-metal laptops as workers, all on the home LAN. Ansible in [`scripts/Ansible/`](../../scripts/Ansible/site.yaml) does every step; this page explains what each step does and how to check it.

## Topology

| Node | Hardware | Lab sizing | Network | Role |
|---|---|---:|---|---|
| `control-plane-1` | Hyper-V VM on the Windows desktop | 2 vCPU / 8 GiB | `eth0`, bridged onto the LAN | etcd, API server, scheduler, controller manager |
| `worker-1` | Dell XPS 13 9360 | 8 threads / 8 GiB | Wi-Fi (`wlp58s0`) | Light workloads, Longhorn replica |
| `worker-2` | Dell XPS 15 9510 | 16 threads / 32 GiB | Wi-Fi (`wlp0s20f3`) | Wazuh indexer, Longhorn replica |

All nodes run Rocky Linux 10.2 with SELinux enforcing. The Wazuh indexer is resource-intensive, so place it on `worker-2` and watch memory pressure on `worker-1`.

## 1. Create the control-plane VM

Run [`scripts/HyperV/New-K8sControlPlaneVM.ps1`](../../scripts/HyperV/New-K8sControlPlaneVM.ps1) from an elevated PowerShell on Windows. It is safe to re-run. It:

- reuses or creates an External virtual switch, so the VM gets its own LAN address instead of a NAT address;
- creates a Generation 2 VM with static memory and the `MicrosoftUEFICertificateAuthority` Secure Boot template, which Rocky's signed bootloader needs;
- turns automatic checkpoints off, because restoring a checkpoint would roll etcd back while the workers keep newer state;
- stops the Windows host sleeping on AC power, since the whole cluster depends on this VM.

Install Rocky Linux 10 from the minimal ISO, then rerun the script with `-EjectIso`.

## 2. Install the laptops

Install Rocky Linux 10 on both laptops. Wi-Fi needs `NetworkManager-wifi` and the card's firmware (`atheros-firmware` for the XPS 13's Killer 1535, `iwlwifi-*-firmware` for Intel cards).

On every node, create a `kubeadmin` account in the `wheel` group and install the lab SSH key:

```bash
ssh-copy-id -i ~/.ssh/k8s_secops_lab.pub kubeadmin@<node-address>
```

The laptops' disks are LUKS-encrypted, so every boot stops at a passphrase prompt on the laptop's own screen. Plan to type it after each power-on, or set up TPM or Clevis+Tang unlocking.

## 3. Write the inventory

```bash
cd scripts/Ansible
cp k8s.ini.example k8s.ini
```

Set each node's current LAN address in `k8s.ini`. The file is ignored by Git because it holds live addresses. Inventory names become node hostnames, and the control-plane endpoint is read from the inventory.

## 4. Run the playbooks

```bash
ansible-playbook site.yaml -K
```

`-K` prompts for the `kubeadmin` sudo password. [`site.yaml`](../../scripts/Ansible/site.yaml) runs, in order:

| Playbook | What it does |
|---|---|
| `node-network.yaml` | Pins each node's current address as static and points DNS at the router |
| `cluster-setup.yaml` | Sets hostnames and `/etc/hosts`, keeps SELinux enforcing, installs containerd and the pinned Kubernetes packages, disables swap, loads kernel modules |
| `baremetal-prep.yaml` | On the laptops only: ignores the lid switch, masks sleep targets, blanks the screen after 60 s, and turns off Wi-Fi power saving |
| `kubeadm-bootstrap.yaml` | Initializes the control plane and joins the workers |
| `helm-install.yaml` | Installs the pinned Helm client |
| `cilium-install.yaml` | Installs Cilium with kube-proxy replacement |
| `cis-hardening.yaml` | Hardens each node to CIS RHEL 10 one at a time, with the deviations in [`docs/cis-deviations.md`](../../docs/cis-deviations.md); reboot each node afterwards |

kubeadm skips its kube-proxy add-on (`skipPhases: addon/kube-proxy`) because Cilium replaces it. Pod (`10.244.0.0/16`) and Service (`10.96.0.0/12`) ranges do not overlap the home LAN.

### SELinux and the control-plane pods

containerd runs with `enable_selinux = true`, so pods are confined as `container_t`. The `container-selinux` policy does not let `container_t` read `kubernetes_file_t`, the label on `/etc/kubernetes`, so etcd, the API server, the scheduler, and the controller manager cannot open their own certificates and crash-loop. `audit.log` shows the denial:

```text
avc: denied { read } ... comm="kube-apiserver" name="sa.key"
  scontext=...container_t...  tcontext=...kubernetes_file_t...
```

The bootstrap playbook writes kubeadm patches to `/etc/kubernetes/patches` that run only those four static pods as `spc_t`. Every other pod stays `container_t`. Confirm with:

```bash
kubectl get pods -A -o custom-columns=POD:.metadata.name,SELINUX:.spec.securityContext.seLinuxOptions.type \
  | grep -v '<none>'
```

### Re-running after a failed init

kubeadm writes `admin.conf` early in `kubeadm init`, so that file existing does not prove init finished. The playbook checks the API server's `/readyz` instead. If `admin.conf` exists but the API server is not serving, the play stops. Fix the cause, run `sudo kubeadm reset -f` on the control plane, and re-run.

## 5. Approve kubelet serving certificates

The kubelet configuration sets `serverTLSBootstrap: true`, so each node requests a serving certificate that an administrator must approve. Until then, `kubectl exec` and `kubectl logs` fail with `tls: internal error`. Follow the review steps in [`../metrics-server/README.md`](../metrics-server/README.md).

## Readiness gate

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status --brief
```

All nodes must be `Ready` with their LAN address as `INTERNAL-IP`, and Cilium must report `OK` with every node reachable before continuing. All of this was observed on the live cluster on 2026-10-26.

## Storage gate

Wazuh uses StatefulSets. Install Longhorn after Cilium is healthy:

```bash
ansible-playbook longhorn-node-prep.yaml -K
kubectl get storageclass
```

By default Longhorn stores replicas in `/var/lib/longhorn` on each worker's root filesystem, and keeps two replicas per volume because there are two workers. Every write is copied over Wi-Fi to the other laptop before it is confirmed, so write latency follows Wi-Fi quality. Document the reclaim policy, backup method, and node-failure recovery before trusting a volume with data.

## Daily power-off

The laptops can be shut down when the lab is not in use. Power everything off together, workers first and the control plane last; start the control plane first. Use `poweroff`, never sleep. To take one laptop out for maintenance, drain it first:

```bash
kubectl drain worker-1 --ignore-daemonsets --delete-emptydir-data
# reboot, unlock LUKS, wait for Ready
kubectl uncordon worker-1
```

## Recovery note

Do not run `kubeadm reset` as a routine troubleshooting step. It is destructive to node state and does not clean every CNI or firewall artifact. Capture logs, etcd health, manifests, and network state first. Use reset only for a half-finished init (above) or when rebuilding a specifically identified node.

## Sources

- [Installing kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)
- [Creating a cluster with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)
- [Customizing components with kubeadm patches](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/control-plane-flags/#patches)
- [Kubernetes version skew policy](https://kubernetes.io/releases/version-skew-policy/)
