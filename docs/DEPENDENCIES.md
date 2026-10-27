# Deployment Dependencies

This document describes the dependencies for the repository's kubeadm SecOps
lab deployment. It is a readiness map, not an installation script: verify each
layer before advancing to the next one.

The separate Kubernetes the Hard Way exercise in `scripts/KTHW.sh` has its own
setup path and is not a dependency of this deployment.

## Dependency chain

```text
Windows Hyper-V host + two bare-metal laptops on one LAN
  -> Rocky Linux 10 on every node + static addresses
    -> reachable Linux nodes + containerd
      -> kubeadm control plane
        -> Cilium CNI + healthy nodes
          -> CSI driver + default StorageClass
            -> Wazuh TLS + secrets + upstream manifests
              -> tested Wazuh content and network policy
```

A later layer depends on every earlier layer. For example, a running kubeadm
API server is not sufficient for Wazuh: Cilium must make the nodes ready, and a
working StorageClass must dynamically provision persistent volumes first.

## Reviewed version pins

[`versions.env`](../versions.env) is the source of truth for reviewed platform
versions.

| Component | Reviewed version | Used by |
|---|---:|---|
| Kubernetes | `v1.37.1` | `kubeadm`, `kubelet`, and `kubectl` package repository |
| containerd | `2.4.2-3.el10` | CRI runtime, `containerd.io` from Docker's RHEL 10 repository |
| Helm | `v4.3.1` | Install pinned charts from the control plane |
| Cilium | `1.20.2` | CNI, kube-proxy replacement, and Hubble |
| Wazuh | `v4.14.8` | Upstream `wazuh/wazuh-kubernetes` release |
| Longhorn chart | `1.12.1` | Replicated block storage and the default StorageClass |
| Metrics Server chart | `3.14.0` | Kubernetes resource metrics API |
| Rocky Linux | `10.2` | Installed from the minimal ISO on the VM and both laptops |

Do not infer compatibility only from this table. Review upstream release notes
before changing a pin, and change the pin, runbook references, and validation
together.

The kubeadm automation consumes these pins from `versions.env`. Keep that file,
the platform runbooks, and validation aligned whenever a version changes.

## 1. Host dependencies

The lab has three machines on one home LAN:

| Machine | Role | Requirements |
|---|---|---|
| Windows 11 Pro desktop | Runs the `control-plane-1` Hyper-V VM | Hyper-V enabled (Pro, Enterprise, or Education), an External virtual switch on the LAN adapter, and power settings that never sleep on AC |
| Dell XPS 13 9360 | `worker-1`, bare metal | Rocky Linux 10 with `NetworkManager-wifi` and `atheros-firmware` for its Killer 1535 Wi-Fi card |
| Dell XPS 15 9510 | `worker-2`, bare metal | Rocky Linux 10 with `NetworkManager-wifi` and Intel Wi-Fi firmware |

[`scripts/HyperV/New-K8sControlPlaneVM.ps1`](../scripts/HyperV/New-K8sControlPlaneVM.ps1) creates the VM: a Generation 2 VM with 2 vCPU, 8 GiB of static memory, a 40 GiB disk, the `MicrosoftUEFICertificateAuthority` Secure Boot template, and automatic checkpoints off. Run it from an elevated PowerShell; it is safe to re-run.

Every node needs a `kubeadmin` account in the `wheel` group with the lab SSH key installed. The laptops' disks are LUKS-encrypted, so each boot waits for a passphrase on the laptop's own screen.

The earlier libvirt host requirements and its Terraform are kept in [`archive/`](../archive/README.md).

## 2. Administrative workstation dependencies

The machine driving the deployment needs:

- Ansible (`ansible-core` 2.21) with the collections in [`scripts/Ansible/requirements.yml`](../scripts/Ansible/requirements.yml);
- `ssh` access to every node as `kubeadmin` with the lab key, ideally through `~/.ssh/config` entries;
- the `kubeadmin` sudo password, which the playbooks prompt for with `-K`;
- `kubectl` compatible with the Kubernetes version-skew policy;
- a Helm client with OCI registry support;
- the Cilium CLI for status and connectivity tests;
- the Hubble CLI when validating flows; and
- Git and outbound HTTPS access to retrieve reviewed upstream releases.

The administrator kubeconfig, kubeadm join command, bootstrap tokens, TLS keys,
and deployment credentials are runtime secrets. Keep them outside Git and
redact them from evidence.

The Ansible workflow installs the pinned Helm client on the control-plane VM so
the administrator kubeconfig does not need to be copied back to the workstation.
The reference workstation is WSL on the Windows desktop, in mirrored networking
mode, so it shares the desktop's LAN address.

## 3. Kubernetes node dependencies

Every control-plane and worker node must have:

- a unique hostname and stable address (set by `cluster-setup.yaml` and
  `node-network.yaml`);
- working node-to-node connectivity and name resolution (the playbook writes
  every node into `/etc/hosts`);
- synchronized time;
- swap disabled, unless kubelet swap support is deliberately configured;
- the `overlay` and `br_netfilter` kernel modules;
- IPv4 forwarding and bridge netfilter sysctls;
- SELinux enforcing, with `container-selinux` and containerd's
  `enable_selinux` so pods are labeled and confined;
- a CRI-compatible runtime, currently containerd with the `systemd` cgroup
  driver;
- matching `kubeadm`, `kubelet`, and `kubectl` packages for the reviewed
  Kubernetes minor; and
- `firewalld` disabled, because Cilium network policy is the lab's traffic
  control (see SG-12 in [`security-gaps.md`](security-gaps.md)); and
- on the laptops only: the lid switch ignored, sleep targets masked, console
  blanking, and Wi-Fi power saving off (`baremetal-prep.yaml`).

Follow [`platform/kubeadm/README.md`](../platform/kubeadm/README.md) for the
bootstrap order. The control plane must omit kube-proxy because Cilium replaces
it.

Readiness gate:

```bash
kubectl get nodes -o wide
kubectl get pods -A
cilium status --wait
cilium connectivity test
```

Do not continue until all nodes are `Ready`, CoreDNS is running, Cilium is
healthy, and the connectivity test passes.

## 4. Cluster service dependencies

### Networking

Cilium is required before workloads can communicate or nodes become ready. Use
the pinned chart and reviewed values in
[`platform/cilium/`](../platform/cilium/README.md). Hubble is the evidence source
for discovering required Wazuh flows before enforcing default-deny policy.

### Persistent storage

Wazuh's manager and indexer use StatefulSets and persistent volume claims. The
cluster therefore requires a CSI driver and a working default `StorageClass`.
The lab uses Longhorn, installed by
[`longhorn-node-prep.yaml`](../scripts/Ansible/longhorn-node-prep.yaml) after
Cilium is healthy. Each worker needs `iscsi-initiator-utils` with `iscsid`
running, which `cluster-setup.yaml` provides, and `nfs-utils` for
ReadWriteMany volumes and backups. Replicas live in `/var/lib/longhorn` on each
worker's root filesystem, two per volume, and every write crosses the Wi-Fi to
the other laptop before it is confirmed.

Before Wazuh deployment, record and test:

- the CSI provisioner and backing storage location;
- the default StorageClass and reclaim policy;
- volume expansion behavior;
- backup and restore procedure; and
- recovery behavior after loss of a worker.

```bash
kubectl get storageclass
kubectl get csidriver
```

An object merely appearing in these commands is not proof that data survives a
node failure. Provision a test claim and exercise the chosen recovery path.

## 5. Wazuh deployment dependencies

Follow [`platform/wazuh/README.md`](../platform/wazuh/README.md) only after the
networking and storage gates pass. The deployment needs:

- the pinned upstream `wazuh/wazuh-kubernetes` release;
- storage-class and resource settings reviewed for this topology;
- TLS certificates generated for the deployment or supplied by the lab PKI;
- replacement credentials stored outside the repository;
- a deliberate private exposure method for dashboard and agent traffic; and
- explicit Cilium allow rules derived from observed required flows.

Custom rules, endpoint settings, and integrations under
[`wazuh/content/`](../wazuh/content/) depend
on a healthy base deployment. Test them with representative positive and
negative events before promotion. Active-response examples remain disabled
prototypes until they receive a safety review and test coverage.

## 6. Repository validation dependencies

Repository validation runs through [pre-commit](https://pre-commit.com), with hook
versions pinned in `.pre-commit-config.yaml`. pre-commit installs the linters itself;
only Terraform must be installed separately, for the hooks that still check the
archived Terraform. Set it up once per clone:

```bash
pipx install pre-commit==4.6.2
pre-commit install          # once per clone: runs the hooks on every git commit
pre-commit run --all-files  # optional: check everything now
```

Then run the narrow syntax or runtime checks relevant to every changed script,
manifest, or runbook. Live-cluster claims require redacted evidence captured
from that cluster.

## Out of scope

These are deliberately not dependencies of this job:

- the separate `scripts/KTHW.sh` learning path;
- Minikube;
- Docker Compose;
- Podman Quadlet; and
- the policy-as-code source maintained in the separate Cloud Operations
  repository.
