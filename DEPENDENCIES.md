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

[`versions.env`](versions.env) is the source of truth for reviewed platform
versions.

| Component | Reviewed version | Used by |
|---|---:|---|
| Kubernetes | `v1.37` minor | `kubeadm`, `kubelet`, and `kubectl` package repository |
| Cilium | `1.20.2` | CNI, kube-proxy replacement, and Hubble |
| Wazuh | `v4.14.8` | Upstream `wazuh/wazuh-kubernetes` release |
| Ubuntu cloud image | `24.04`, release `20260926` | VM provisioning script |

Do not infer compatibility only from this table. Review upstream release notes
before changing a pin, and change the pin, runbook references, and validation
together.

The kubeadm automation consumes these pins from `versions.env`. Keep that file,
the platform runbooks, and validation aligned whenever a version changes.

## 1. KVM host dependencies

The host must be a Linux system with hardware virtualization enabled and enough
capacity for three VMs. The current reference topology needs at least 10 vCPUs,
20 GiB of assignable memory, and 90 GiB of virtual disk capacity, plus headroom
for the host and Wazuh data growth.

Run [`scripts/check-host.sh`](scripts/check-host.sh) to inspect CPU virtualization,
memory, disk space, the libvirt network, and the libvirt service.

The VM provisioning path in
[`scripts/create-kvm-cluster-vms.sh`](scripts/create-kvm-cluster-vms.sh) requires:

| Command or resource | Purpose | Ubuntu package or source |
|---|---|---|
| `virsh` | Manage libvirt networks and domains | `libvirt-clients` |
| `virt-install` | Define and start each VM | `virtinst` |
| `qemu-img` | Create qcow2 overlay disks | `qemu-utils` |
| `cloud-localds` | Build cloud-init seed images | `cloud-image-utils` |
| `sha256sum` | Verify the pinned cloud image | `coreutils` |
| `sudo` | Perform scoped system libvirt operations | `sudo` |
| SSH public key | Provide key-only VM access | User-managed; never commit the private key |
| Ubuntu 24.04 cloud image | Backing image for all three VMs | Pinned filename and SHA-256 in the script |
| Active libvirt network | Give the VMs addressability | Default name: `default` |

Package names above are for an Ubuntu host. On another distribution, install
the packages that provide the same commands rather than copying those names.

The provisioning script assigns 4 GiB to the control plane and 8 GiB to each
worker, matching the reference starting point. Measure memory pressure and
indexing latency before increasing event volume.

## 2. Administrative workstation dependencies

The machine driving the deployment needs:

- `ssh` and `scp` access to every VM;
- name resolution for the stable Kubernetes API endpoint;
- `kubectl` compatible with the Kubernetes version-skew policy;
- Helm 3 with OCI registry support;
- the Cilium CLI for status and connectivity tests;
- the Hubble CLI when validating flows; and
- Git and outbound HTTPS access to retrieve reviewed upstream releases.

The administrator kubeconfig, kubeadm join command, bootstrap tokens, TLS keys,
and deployment credentials are runtime secrets. Keep them outside Git and
redact them from evidence.

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

Follow [`platform/kubeadm/README.md`](platform/kubeadm/README.md) for the
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
[`platform/cilium/`](platform/cilium/README.md). Hubble is the evidence source
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

Follow [`platform/wazuh/README.md`](platform/wazuh/README.md) only after the
networking and storage gates pass. The deployment needs:

- the pinned upstream `wazuh/wazuh-kubernetes` release;
- storage-class and resource settings reviewed for this VM topology;
- TLS certificates generated for the deployment or supplied by the lab PKI;
- replacement credentials stored outside the repository;
- a deliberate private exposure method for dashboard and agent traffic; and
- explicit Cilium allow rules derived from observed required flows.

Custom rules, endpoint settings, and integrations under `wazuh/content/` depend
on a healthy base deployment. Test them with representative positive and
negative events before promotion. Active-response examples remain disabled
prototypes until they receive a safety review and test coverage.

## 6. Repository validation dependencies

Repository validation requires Python 3 and Bash. Before a pull request, run:

```bash
python3 scripts/validate_repo.py
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
