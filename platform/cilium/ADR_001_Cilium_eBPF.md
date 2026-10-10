# ADR 001: Selection of Cilium for Zero-Trust Network Enforcement

**Status:** Accepted
**Date:** 2026-02-24
**Context:** Workload isolation on the kubeadm VM lab — enforcing policy between Wazuh components and supporting services where Pod IPs are not stable across rescheduling.

---

## Decision

Cilium with its eBPF data plane is the CNI for Kubernetes network policy enforcement in this environment. It also replaces kube-proxy and provides Hubble flow telemetry.

---

## Rationale

### 1. Identity-Based Security (Zero Trust)

IP-based rules break when Pods are rescheduled. Cilium assigns identities from Kubernetes metadata and enforces policy on those identities rather than relying on transient Pod addresses. Policy can therefore restrict lateral movement between Wazuh and supporting workloads as their placement changes.

- **MITRE:** T1210 (Exploitation of Remote Services) — lateral movement between workloads requires an explicit allow policy
- **STRIDE:** Tampering — a compromised container cannot reach adjacent workloads without a policy grant

### 2. eBPF Performance and Kernel-Level Enforcement

Cilium's eBPF data plane replaces kube-proxy in this lab and enforces network policy in the kernel. The control plane is initialized without the kube-proxy add-on so there is one deliberate service-routing path.

Transparent WireGuard encryption between nodes is available at the same layer, requiring no sidecar.

### 3. L7 Visibility via Hubble

Hubble surfaces flows and policy verdicts per workload identity. This provides evidence for the Wazuh allow-list and makes rejected or unexpected connections visible during deployment testing.

- **MITRE:** T1048 (Exfiltration Over Alternative Protocol) — Hubble detects unexpected outbound flows from a model-serving container
- **NIST 800-53:** AU-12 (Audit Record Generation)

### 4. Global Default Deny

The baseline policy (`global_default_deny.yaml`) denies all ingress and egress by default. Every communication path is an explicit allow — the minimum required for the workload to function.

- **NIST 800-53:** SC-7 (Boundary Protection), AC-4 (Information Flow)
- **OWASP Top 10:2025:** A01 (Broken Access Control)

---

## Trade-offs

| Factor | Detail |
|---|---|
| Kernel requirement | Every VM kernel must meet the requirement for the pinned Cilium release |
| Complexity | Policy debugging requires `hubble observe` familiarity — steeper than iptables |
| Scope | This ADR covers the self-hosted VM lab. Production requires a separate availability, storage, and policy review. |

---

## Compliance Mapping

| Control | Mapping |
|---|---|
| NIST 800-53 SC-7 | Boundary Protection — default deny enforced at network layer |
| NIST 800-53 SC-8 | Transmission Integrity — WireGuard encryption available |
| NIST 800-53 AC-4 | Information Flow — explicit allow-list per workload identity |
| MITRE T1210 | Exploitation of Remote Services — lateral movement blocked |
| MITRE T1048 | Exfiltration — Hubble detects unexpected egress flows |
