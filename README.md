# Kubernetes SecOps Platform

> **Field Project 02 of the [Cloud Operations Engineering](https://github.com/CloudSec-Jay/cloud-ops-engineering) system.** Each project lives in its own repository and links back to the hub. [Portfolio site](https://cloudsec-jay.github.io/cloud-ops-engineering/) · [Project site](https://cloudsec-jay.github.io/k8s-secops-platform/)

A self-hosted security lab that consolidates the former Wazuh operations and Kubernetes platform work as Field Project 02. It is a hybrid `kubeadm` cluster, with a Hyper-V virtual machine as the control plane and two bare-metal laptops as workers, networked and observed with Cilium, and running the upstream Wazuh Kubernetes deployment.

## Architecture

![Hybrid lab architecture: a Windows desktop runs the admin workstation and the Hyper-V control-plane VM; two bare-metal laptop workers share one home Wi-Fi LAN with it. Cilium provides the eBPF dataplane, a default deny, and an L2-announced Gateway at 10.0.0.56 reachable only from the desktop. Longhorn keeps one replica per laptop. Wazuh and Argo CD are planned.](docs/site/architecture.svg)

| # | Flow | Status |
| :--- | :--- | :--- |
| 1 | Admin workstation to the nodes over SSH, for Ansible and `kubectl` | Live |
| 2 | Browser to the Gateway VIP `10.0.0.56` over HTTPS, admin desktop only | Live |
| 3 | Longhorn replica sync between the two laptops over Wi-Fi | Live |
| 4 | Node DNS and internet egress through the home router | Live |
| 5 | Package and container image downloads | Live |
| 6 | Wazuh agent enrollment and events (1515 / 1514) | Planned |

Every node has its own address on the home LAN; there is no NAT between nodes. Rocky Linux 10.2, Kubernetes v1.37.1, containerd 2.4.2, and Cilium 1.20.2 run on all three, with SELinux enforcing. Exact pins are in [`versions.env`](versions.env).

## Repository map

| Path | Purpose |
|---|---|
| [`scripts/HyperV/`](scripts/HyperV/New-K8sControlPlaneVM.ps1) | PowerShell script that creates the control-plane VM on a LAN-bridged Hyper-V switch |
| [`scripts/Ansible/`](scripts/Ansible/site.yaml) | Node networking, node preparation, laptop power settings, kubeadm bootstrap, and platform installs |
| [`platform/kubeadm/`](platform/kubeadm/README.md) | Node prerequisites and the kubeadm bootstrap sequence |
| [`platform/cilium/`](platform/cilium/README.md) | Pinned Cilium values, network policies, LB-IPAM, and Hubble validation |
| [`platform/gateway-api/`](platform/gateway-api/README.md) | Gateway API listener and routes for `*.lab.internal` |
| [`platform/cert-manager/`](platform/cert-manager/README.md) | Private lab CA and certificate automation |
| [`platform/metrics-server/`](platform/metrics-server/README.md) | Resource metrics with verified kubelet TLS |
| [`platform/argocd/`](platform/argocd/README.md) | GitOps controller and Application definitions (in progress) |
| [`platform/wazuh/`](platform/wazuh/README.md) | Upstream Wazuh Kubernetes deployment runbook |
| [`wazuh/content/`](wazuh/content/README.md) | Migrated endpoint configs, rules, SCA content, integrations, and runbooks |
| [`archive/`](archive/) | Retired material, kept for reference: the libvirt Terraform, KVM host networking, and local-path storage |
| [`docs/PROBLEM_SOLVED.md`](docs/PROBLEM_SOLVED.md) | Engineering postmortem & troubleshooting case studies (storage, networking, disk pressure) |
| [`docs/site/`](docs/site/index.html) | GitHub Pages project site |

## Deployment path

1. Create the control-plane VM with [`scripts/HyperV/New-K8sControlPlaneVM.ps1`](scripts/HyperV/New-K8sControlPlaneVM.ps1) and install Rocky Linux 10 on it and on both laptops, each with a `kubeadmin` account and SSH key access.
2. Copy [`scripts/Ansible/k8s.ini.example`](scripts/Ansible/k8s.ini.example) to `k8s.ini` and set each node's LAN address.
3. Run `ansible-playbook site.yaml -K` from `scripts/Ansible/`. It pins static node addresses, prepares the nodes, keeps the laptops awake with their lids closed, bootstraps kubeadm, and installs Helm and Cilium. Details in [`platform/kubeadm/README.md`](platform/kubeadm/README.md).
4. Review and approve the kubelet serving certificate requests as described in [`platform/metrics-server/README.md`](platform/metrics-server/README.md).
5. Install Longhorn with `longhorn-node-prep.yaml`; Wazuh's StatefulSets require persistent volumes.
6. Follow [`platform/wazuh/README.md`](platform/wazuh/README.md) to stage the pinned upstream Wazuh manifests, generate certificates, replace default credentials, and deploy.
7. Apply migrated Wazuh content only after testing it with representative positive and negative events.

## Deliberate boundaries

- No Minikube workflow is included; this lab targets real nodes managed with `kubeadm`.
- No Docker Compose or Podman Quadlet Wazuh runtime is included.
- Policy-as-code remains in [Cloud Operations policy-as-code](https://github.com/CloudSec-Jay/cloud-ops-engineering/tree/main/security/policy-as-code) and is linked rather than duplicated.
- Upstream Wazuh Kubernetes manifests are staged at deployment time instead of copied into this repository. This keeps the vendor boundary and version pin explicit.
- Active-response files are prototypes. They are not enabled by the platform deployment.

## Validation

Run the repository checks before opening a pull request:

```bash
pipx install pre-commit==4.6.2
pre-commit install          # once per clone: runs the hooks on every git commit
pre-commit run --all-files  # optional: check everything now
```

The hooks are defined in `.pre-commit-config.yaml`, and CI runs the same hooks on every push and pull request. They check XML and YAML syntax, whitespace, Ansible best practices, and the formatting and configuration of the archived Terraform. Runtime validation still requires the live cluster.

## Documentation

- Operational case study & troubleshooting log: [`docs/PROBLEM_SOLVED.md`](docs/PROBLEM_SOLVED.md)
- Deployment prerequisites and dependency order: [`docs/DEPENDENCIES.md`](docs/DEPENDENCIES.md)
- Architecture and trust boundaries: [`docs/architecture.md`](docs/architecture.md)
- Project site: <https://cloudsec-jay.github.io/k8s-secops-platform/>
- Source: <https://github.com/CloudSec-Jay/k8s-secops-platform>
- Operations and limitations: [`docs/operations.md`](docs/operations.md)

## License

Original portfolio material is covered by [`LICENSE`](LICENSE). Third-party material retains its upstream terms; see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
