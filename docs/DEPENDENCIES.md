# Deployment Dependencies

This document describes the dependencies for the repository's kubeadm SecOps
lab deployment. It is a readiness map, not an installation script: verify each
layer before advancing to the next one.

The separate Kubernetes the Hard Way exercise in `scripts/KTHW.sh` has its own
setup path and is not a dependency of this deployment.

## Dependency chain

```text
Linux KVM host
  -> libvirt network + Ubuntu VM images
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
| containerd | `2.2.2-0ubuntu1.1` | CRI runtime from the Ubuntu archive |
| Helm | `v4.3.1` | Install pinned charts from the control plane |
| Cilium | `1.20.2` | CNI, kube-proxy replacement, and Hubble |
| Wazuh | `v4.14.8` | Upstream `wazuh/wazuh-kubernetes` release |
| local-path-provisioner | `v0.0.37` | Dynamic host-path storage for the lab |
| Metrics Server chart | `3.14.0` | Kubernetes resource metrics API |
| Ubuntu cloud image | `26.04`, release `20261016` | VM provisioning with Terraform |

Do not infer compatibility only from this table. Review upstream release notes
before changing a pin, and change the pin, runbook references, and validation
together.

The kubeadm automation consumes these pins from `versions.env`. Keep that file,
the platform runbooks, and validation aligned whenever a version changes.

## 1. KVM host dependencies

The host must be a Linux system with hardware virtualization enabled and enough
capacity for four VMs. The current reference topology allocates 14 vCPUs,
28 GiB of memory, and four sparse 90 GiB virtual disks, plus any optional backup
disk passed through to `worker-3`.

Run [`scripts/check-host.sh`](../scripts/check-host.sh) to inspect CPU
virtualization, memory, disk space, the libvirt network, and the libvirt
service.

VMs are provisioned by Terraform in [`terraform/`](../terraform/README.md), which
runs on the workstation and drives libvirt on the host over SSH. The host
requires:

| Command or resource | Purpose | Ubuntu package or source |
|---|---|---|
| `libvirtd` with QEMU/KVM | Run the VMs | `libvirt-daemon-system`, `qemu-system-x86` |
| `virsh` | Inspect libvirt pools, networks, and domains | `libvirt-clients` |
| `sshd` | Accept the provider's key-based SSH connection | `openssh-server` |
| Account in the `libvirt` group | Manage `qemu:///system` without interactive `sudo` | User-managed |
| Active libvirt network | Give the VMs addressability | Default name: `default` |
| Active libvirt storage pool | Hold the base image and VM disks | Default name: `default` |

The workstation additionally needs Terraform and the pinned Ubuntu 26.04 cloud
image; see the Terraform README for the image path, SHA-256, and SSH keys.

Package names above are for an Ubuntu host. On another distribution, install
the packages that provide the same commands rather than copying those names.

The Terraform node map assigns 4 GiB to the control plane and 8 GiB to each
worker, matching the reference starting point. Measure memory pressure and
indexing latency before increasing event volume.

## 2. Administrative workstation dependencies

The machine driving the deployment needs:

- `ssh` and `scp` access to every VM;
- name resolution for the stable Kubernetes API endpoint;
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

## 3. Kubernetes node dependencies

Every control-plane and worker VM must have:

- a unique hostname and stable address;
- working node-to-node connectivity and forward/reverse name resolution;
- synchronized time;
- swap disabled, unless kubelet swap support is deliberately configured;
- the `overlay` and `br_netfilter` kernel modules;
- IPv4 forwarding and bridge netfilter sysctls;
- a CRI-compatible runtime, currently containerd with the `systemd` cgroup
  driver;
- matching `kubeadm`, `kubelet`, and `kubectl` packages for the reviewed
  Kubernetes minor; and
- only the firewall ports required by Kubernetes, Cilium, Wazuh, and the chosen
  administration path.

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
The repository intentionally does not select a storage implementation because
that decision changes durability, backup, and node-failure recovery.

Before Wazuh deployment, record and test:

- the CSI provisioner and backing storage location;
- the default StorageClass and reclaim policy;
- volume expansion behavior;
- backup and restore procedure; and
- recovery behavior after loss of a worker VM.

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
- storage-class and resource settings reviewed for this VM topology;
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
only Terraform must be installed separately. Set it up once per clone:

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
