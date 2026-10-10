# Repository Guidance

## Scope

This repository targets a self-hosted, multi-VM Kubernetes security lab. Use kubeadm, containerd-compatible tooling, Cilium, and the upstream Wazuh Kubernetes deployment.

## Boundaries

- Do not add Minikube, Docker Compose, or Podman Quadlet deployment paths.
- Do not commit secrets, kubeconfig files, certificates, generated vendor trees, or live environment output.
- Keep policy-as-code in `CloudSec-Jay/cloud-ops-engineering/security/policy-as-code`; link to it instead of copying it here.
- Treat active-response examples as disabled prototypes until they have explicit safety review and test coverage.
- Pin third-party versions and record the upstream source.

## Validation

Run `python3 scripts/validate_repo.py` and relevant runtime checks before committing. Claims about a live cluster require redacted evidence from that cluster.
