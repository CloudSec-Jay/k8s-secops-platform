# kubeadm VM Cluster

This runbook bootstraps a self-hosted Kubernetes cluster on Linux virtual machines. It intentionally leaves VM provisioning, DNS, and storage implementation outside Kubernetes so each dependency is visible and testable.

## Reference topology

| Role | Example DNS name | Minimum lab sizing | Notes |
|---|---|---:|---|
| Control plane | `k8s-api.lab.internal` | 2 vCPU / 4 GiB | Use a stable DNS name or virtual IP from the beginning |
| Worker 1 | `k8s-worker-01.lab.internal` | 4 vCPU / 8 GiB | Wazuh workloads and persistent volumes |
| Worker 2 | `k8s-worker-02.lab.internal` | 4 vCPU / 8 GiB | Wazuh workloads and persistent volumes |

The Wazuh indexer is resource-intensive. Treat these figures as a starting point for a lab, measure pressure and disk latency, and increase resources before adding production-like event volume.

## Before bootstrap

On every VM:

1. Assign a unique hostname and stable address.
2. Confirm full node-to-node connectivity and working forward/reverse DNS.
3. Disable swap or configure kubelet swap support deliberately.
4. Enable IPv4 forwarding and required bridge netfilter modules.
5. Install a CRI-compatible runtime such as containerd with the `systemd` cgroup driver.
6. Install matching `kubeadm`, `kubelet`, and `kubectl` packages from the repository for `KUBERNETES_MINOR` in [`versions.env`](../../versions.env), then hold those packages.
7. Open only the ports required by the Kubernetes components, Cilium, Wazuh enrollment/event traffic, and your chosen dashboard exposure path.

Use the [official kubeadm installation guide](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/) for distribution-specific package commands. Kubernetes publishes a separate package repository for each minor release, so do not silently substitute a different repository.

## Initialize the control plane

The platform uses Cilium's kube-proxy replacement. Initialize kubeadm without the kube-proxy add-on:

```bash
sudo kubeadm init \
  --control-plane-endpoint k8s-api.lab.internal:6443 \
  --pod-network-cidr 10.244.0.0/16 \
  --skip-phases addon/kube-proxy
```

Choose Pod and Service CIDRs that do not overlap any VM, VPN, or home-lab networks. Preserve the generated join command as a secret; a bootstrap token can authorize a node to join the cluster.

Configure `kubectl` for a non-root administrator exactly as printed by `kubeadm init`, then verify that the control-plane node exists. `NotReady` is expected until the CNI is installed.

## Install Cilium before joining workloads

Follow [`../cilium/README.md`](../cilium/README.md). Cilium must be healthy before scheduling Wazuh or enforcing default-deny policies.

## Join worker VMs

Run the short-lived `kubeadm join` command from the init output on each worker. If it expired, create a new one on the control plane:

```bash
sudo kubeadm token create --print-join-command
```

Do not paste join tokens, discovery hashes, or administrator kubeconfigs into issues, logs, or Git.

## Readiness gate

```bash
kubectl get nodes -o wide
kubectl get pods -A
cilium status --wait
cilium connectivity test
```

All nodes must be `Ready`, Cilium must be healthy, CoreDNS must be running, and the connectivity test must pass before continuing.

## Storage gate

Wazuh uses StatefulSets. Install and validate a CSI-backed default `StorageClass` suitable for the VM environment before deploying it:

```bash
kubectl get storageclass
kubectl get csidriver
```

Document the backing path or storage system, reclaim policy, expansion behavior, backup method, and node-failure recovery. A default StorageClass existing is not proof that retained volumes survive a VM loss.

## Recovery note

Do not run `kubeadm reset` as a routine troubleshooting step. It is destructive to node state and does not clean every CNI or firewall artifact. Capture logs, etcd health, manifests, and network state first; use the upstream reset procedure only when rebuilding a specifically identified node.

## Sources

- [Installing kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)
- [Creating a cluster with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)
- [Kubernetes version skew policy](https://kubernetes.io/releases/version-skew-policy/)
