# Kubernetes SecOps Platform

> **Field Project 02 of the [Cloud Operations Engineering](https://github.com/CloudSec-Jay/cloud-ops-engineering) system.** Each project lives in its own repository and links back to the hub. [Portfolio site](https://cloudsec-jay.github.io/cloud-ops-engineering/) · [Project site](https://cloudsec-jay.github.io/k8s-secops-platform/)

A self-hosted security lab that consolidates the former Wazuh operations and Kubernetes platform work as Field Project 02. The target is a multi-VM Kubernetes cluster bootstrapped with `kubeadm`, networked and observed with Cilium, and running the upstream Wazuh Kubernetes deployment.

## Architecture

```text
Linux endpoints / Kubernetes nodes
              |
       Wazuh agent traffic
              v
+---------------------------------------------+
| kubeadm cluster on virtual machines         |
|                                             |
| Cilium CNI + Hubble                         |
|   |                                         |
|   +-- default-deny network boundaries       |
|                                             |
| Wazuh manager -> Wazuh indexer -> dashboard |
|        |              |             |       |
|        +------ persistent storage ---+       |
+---------------------------------------------+
```

## Repository map

| Path | Purpose |
|---|---|
| [`platform/kubeadm/`](platform/kubeadm/README.md) | VM prerequisites and kubeadm bootstrap sequence |
| [`platform/cilium/`](platform/cilium/README.md) | Pinned Cilium values, network boundaries, and Hubble validation |
| [`platform/manifests/`](platform/manifests/) | Namespace and baseline Kubernetes manifests |
| [`platform/wazuh/`](platform/wazuh/README.md) | Upstream Wazuh Kubernetes deployment runbook for the VM cluster |
| [`wazuh/content/`](wazuh/content/README.md) | Migrated endpoint configs, rules, SCA content, integrations, and runbooks |
| [`PROBLEM_SOLVED.md`](PROBLEM_SOLVED.md) | Engineering postmortem & troubleshooting case studies (storage, networking, disk pressure) |
| [`docs/site/`](docs/site/index.html) | GitHub Pages project site |

## Deployment path

1. Prepare at least one control-plane VM and two worker VMs with a supported Linux distribution, a CRI-compatible runtime, synchronized time, unique hostnames, and non-overlapping network ranges.
2. Bootstrap the cluster with [`platform/kubeadm/README.md`](platform/kubeadm/README.md).
3. Install Cilium using [`platform/cilium/values.yaml`](platform/cilium/values.yaml) and verify Hubble connectivity.
4. Install a CSI-backed default `StorageClass`; Wazuh's StatefulSets require persistent volumes.
5. Follow [`platform/wazuh/README.md`](platform/wazuh/README.md) to stage the pinned upstream Wazuh manifests, generate certificates, replace default credentials, and deploy.
6. Apply migrated Wazuh content only after testing it with representative positive and negative events.

## Deliberate boundaries

- No Minikube workflow is included; this lab targets VMs managed with `kubeadm`.
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

The hooks are defined in `.pre-commit-config.yaml`, and CI runs the same hooks on every push and pull request. They check XML and YAML syntax, whitespace, Ansible best practices, and Terraform formatting and configuration. Runtime validation still requires the target VM cluster.

## Documentation

- Operational case study & troubleshooting log: [`PROBLEM_SOLVED.md`](PROBLEM_SOLVED.md)
- Deployment prerequisites and dependency order: [`DEPENDENCIES.md`](DEPENDENCIES.md)
- Project site: <https://cloudsec-jay.github.io/k8s-secops-platform/>
- Source: <https://github.com/CloudSec-Jay/k8s-secops-platform>
- Operations and limitations: [`docs/operations.md`](docs/operations.md)

## License

Original portfolio material is covered by [`LICENSE`](LICENSE). Third-party material retains its upstream terms; see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
