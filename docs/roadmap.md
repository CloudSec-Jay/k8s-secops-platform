# Cluster Roadmap

Services planned for the lab, in build order. Each one ships in its own branch and pull request, with its Cilium policy, a deliberate restart test, and an update to the project site.

Memory figures are lab-sized estimates. Measure before and after each addition with `free -h` on each node and `kubectl top nodes` / `kubectl top pods -A` in the cluster.

## Next up

Open work as of 2026-10-27, in the order it should be done. Each item names the gap or doc it closes.

1. [ ] **Deploy Wazuh** on the hybrid cluster. Rotate the upstream example secrets first ([SG-01](security-gaps.md#sg-01-wazuh-runs-on-the-upstream-example-secrets)), apply `manifests/wazuh.yaml` before the workload, place the indexer on worker-2, and share `10.0.0.56` for agent ports 1514/1515 with `lbipam.cilium.io/sharing-key`.
2. [ ] **Wazuh agents on the nodes** for file-integrity monitoring, the compensating control for AIDE ([cis-deviations.md](cis-deviations.md)).
3. [ ] **Argo CD**: write the `apps/` and `projects/` TODOs, starting with `cilium-policies`.
4. [ ] **Lock the nodes down to the API** (run exercises A and B below first). Manage the cluster with `kubectl` from the admin desktop over the API server's mTLS, using a per-user kubeconfig (`kubeadm kubeconfig user`) bound by RBAC instead of `admin.conf`. Restrict SSH to key-only from the desktop ([SG-02](security-gaps.md#sg-02-every-node-accepts-ssh-passwords-from-the-lan); authorize the lab key on worker-2 first), and enable the Cilium host firewall so nodes accept only Kubernetes and Cilium ports from each other ([SG-12](security-gaps.md#sg-12-node-traffic-is-not-filtered)). Roll the host policy out in audit mode first. Admin UIs such as Hubble then open with `kubectl port-forward` from the desktop.
5. [ ] **Encrypt Secrets at rest** (run exercise E below first; [SG-03](security-gaps.md#sg-03-no-api-audit-logging-or-secrets-encryption-at-rest)). An `EncryptionConfiguration` on the control plane, wired in through `kubeadm-config.yaml.j2`, then rewrite existing Secrets. Protects the lab CA key in `cert-manager/lab-root-ca-keypair`.

### SecOps exercises: detect, then fix

Each open gap is first attacked harmlessly and detected, with redacted evidence and a triage runbook in `wazuh/content/runbooks/`, and only then closed. Re-run the attack after the fix to show the detection and the fix both work. These need Wazuh (item 1) and the node agents (item 2).

- [ ] **A. SSH password brute force** ([SG-02](security-gaps.md#sg-02-every-node-accepts-ssh-passwords-from-the-lan)): a short, rate-limited failed-login run against a node from another LAN host. Evidence: Wazuh authentication-failure and brute-force alerts with the source IP. Then key-only, desktop-only SSH; re-run and show the connections are refused.
- [ ] **B. Network scan of the nodes** ([SG-12](security-gaps.md#sg-12-node-traffic-is-not-filtered)): an `nmap` scan of all three nodes from worker-1 or a phone. Evidence: the scan in Wazuh or Hubble. Then the Cilium host firewall; re-scan and show only the allowed ports answer.
- [ ] **C. Continuous CIS compliance**: Wazuh SCA scoring every node against the CIS RHEL 10 benchmark, alerting when a hardened setting drifts. Test by reverting one setting on one node and restoring it.
- [ ] **D. Policy drops as security events**: forward Hubble's dropped flows into Wazuh, so a pod reaching for something the default deny forbids raises an alert. Test with a pod in an unapproved namespace.
- [ ] **E. Secret access** ([SG-03](security-gaps.md#sg-03-no-api-audit-logging-or-secrets-encryption-at-rest)): enable API audit logging, ship it to Wazuh, and alert on reads of `cert-manager/lab-root-ca-keypair`. Then encrypt Secrets at rest and show etcd holds only ciphertext.
- [ ] **F. Recovery drill**: power off a worker mid-write and restore a Longhorn volume from backup; record the result next to INC-05 in [PROBLEM_SOLVED.md](PROBLEM_SOLVED.md).

Smaller follow-ups:

- [ ] CIS PAM controls (5.3.1.x): a supervised run with `rhel10cis_disruption_high: true --tags authselect`, or record them as not applied.
- [ ] CIS 1.4.1 GRUB password: a `grub2-mkpasswd-pbkdf2` hash in ansible-vault.
- [ ] CIS manual reviews flagged by the role: 1.1.1.11, 1.2.1.4, 2.1.22, 7.1.13.
- [ ] kubelet `shutdownGracePeriod`, so power-off stops pods cleanly and `kube-apiserver` no longer holds shutdown for 90 s.
- [ ] DHCP reservation for the admin desktop (`10.0.0.79`), which the Gateway policy allows by address.
- [ ] A login (Authentik or oauth2-proxy) in front of the Longhorn UI before the Gateway admits more than the desktop.
- [ ] Unattended LUKS unlock (TPM2 or Clevis + Tang) and USB Ethernet for the laptops; both are in Phase 1 below.

## Rules for every addition

- **Policy first.** The cluster is default-deny. Write the Cilium allow rules with the service, then restart it on purpose and watch Hubble for drops. Rules written only from observed flows miss reconnect-time traffic (see INC-05 in [`PROBLEM_SOLVED.md`](PROBLEM_SOLVED.md)).
- **Pin versions** in `versions.env`.
- **Preview node changes** with `ansible-playbook --check --diff` before applying them to the laptops.
- **Set memory limits** on every workload.

## Phase 1: Platform

| Service | Purpose | Approx. RAM | Notes |
|---|---|---|---|
| Hybrid rebuild | Hyper-V control plane, bare-metal laptop workers, no NAT | – | **Done 2026-10-26.** Replaced the four libvirt VMs (including worker-3, added 2026-10-21). All nodes Ready, Cilium healthy, SELinux enforcing with the control plane scoped to `spc_t`. Terraform and the KVM host networking moved to `archive/`. |
| LAN service pool and Gateway | One LAN address for the Gateway | – | **Done 2026-10-27.** `10.0.0.56`, never assigned by the router; `https://storage.lab.internal` serves the Longhorn UI with the lab CA, admin desktop only. Add a login (Authentik or oauth2-proxy) before widening access |
| USB Ethernet for the laptops | Stable node links for Longhorn replication | – | Both workers are on 2.4 GHz Wi-Fi; Longhorn waits on every write to the other laptop |
| Unattended LUKS unlock | Laptops boot without a typed passphrase | – | TPM2 (`systemd-cryptenroll`) or Clevis + Tang on the home network; decide the theft tradeoff first |
| Baseline Cilium policies in `site.yaml` | Rebuilds come up default-deny without a manual step | – | The 2026-10-21 and 2026-10-26 rebuilds came up allow-all until the policies were applied by hand. Apply order: `kube-system.yaml` (after `node-network.yaml` pins router DNS), the other namespace bundles, `cluster.yaml`, then `lb.yaml`. |
| metrics-server | Enables `kubectl top` | ~50 MB | **Done 2026-10-21** on the libvirt build; reinstall on the hybrid cluster. Verifies kubelet certificates against the cluster CA; no `--kubelet-insecure-tls`. Renewed kubelet serving CSRs need approval each year. |
| Longhorn | Replicated block storage across workers | 1–1.5 GB | **Reworked 2026-10-26 for bare metal:** replicas in `/var/lib/longhorn` on each laptop's 70 GiB root filesystem (about 50 GiB usable after the 25% reserve), two replicas per volume, iSCSI and a multipath blacklist from Ansible. Both laptops have far more free space in `/home`, which can be added later as a second Longhorn disk. **Installed 2026-10-27:** Longhorn 1.12.1 is the default StorageClass; a test volume came up healthy with one replica per laptop, with no policy drops under the cluster default deny. Replicas now protect against a laptop failing, at the cost of Wi-Fi write latency. |
| Garage | S3 backup target for Longhorn | ~100–200 MB | On the 1 TB USB SSD now attached to worker-2. Uses the SSD directly, never Longhorn, so backups survive a Longhorn failure. Pinned to worker-2; backups pause while that laptop is off. Run a restore test before relying on it. |
| Pod anti-affinity | Keep the Wazuh master and worker managers on different nodes | – | Easier once Longhorn removes node-pinned volumes |
| Kyverno | Admission policy: block or fix unsafe workloads | 300–600 MB | Audit mode first, then enforce. Document why Kyverno here while the portfolio uses OPA elsewhere. |

## Phase 2: GitOps

| Service | Purpose | Approx. RAM | Notes |
|---|---|---|---|
| Argo CD | Deploy the cluster from this GitHub repo | 0.5–1 GB | Pulls from GitHub over outbound connections only; nothing exposed. Everything after this phase deploys through it. |

## Phase 3: Access

| Service | Purpose | Approx. RAM | Notes |
|---|---|---|---|
| cert-manager + private CA | Issue certificates for every app | ~200 MB | **Done 2026-10-22.** v1.21.2 with private Root CA and ClusterIssuer (`lab-ca-issuer`) under Cilium zero-trust allow policy. |
| AdGuard Home | Local DNS for the `.internal` domain | ~100 MB | Also blocks ads on the home network |
| Cilium Gateway API | One LAN address, apps routed by hostname | ~100 MB | Built into Cilium; uses Kubernetes Gateway API v1.6.1 standard CRDs; single 443 LAN VIP. |

## Phase 4: Observability

| Service | Purpose | Approx. RAM | Notes |
|---|---|---|---|
| Prometheus | Metrics collection | 1–2 GB | Short retention (about 7 days) and a memory limit from the start |
| Grafana, Alertmanager, exporters | Dashboards and alerts | ~500 MB | Installed with Prometheus via kube-prometheus-stack |
| Uptime Kuma | Uptime checks for every service | ~200 MB | Include a check that `cluster_control -l` lists every Wazuh manager |
| Homepage | Dashboard linking to every service | ~100 MB | |

## Phase 5: Security

| Service | Purpose | Approx. RAM | Notes |
|---|---|---|---|
| Trivy Operator | Vulnerability scanning of running workloads | ~300 MB | |
| Authentik | Single sign-on for Grafana, Argo CD, Nextcloud | ~1 GB | Heaviest addition. Check headroom before installing. |

## Phase 6: Apps

| Service | Purpose | Approx. RAM | Notes |
|---|---|---|---|
| MySQL | Database for Nextcloud | 0.5–1 GB | On Longhorn |
| Nextcloud + Redis | File sync and sharing | 0.5–1 GB | Real personal data: back it up off the laptop from day one |

## Phase 7: Project consolidation

Consolidate and reorganize the project files only after the planned platform,
security, and application work is complete. Inventory files before moving them,
update references and documentation in small reviewable changes, and preserve the
boundary between the KTHW learning path and the kubeadm deployment path. Do not
include generated files, credentials, kubeconfigs, certificates, vendor trees, or
live environment output.

## Memory budget

| | |
|---|---|
| Control plane | 8 GiB Hyper-V VM; the Windows desktop has 39 GiB in total (2026-10-26) |
| Worker capacity | 7.4 GiB on worker-1 (XPS 13) and 30 GiB on worker-2 (XPS 15) |
| Baseline per node (system pods, 2026-10-21 on the libvirt build) | Control plane 1.1 GiB; each worker 1.1–1.2 GiB |
| New workloads (all phases) | about 7–10 GB |

The Wazuh indexer and Prometheus are the largest consumers and belong on worker-2. worker-1 cannot absorb worker-2's pods if worker-2 fails, so the heavy workloads stop until it returns.

## Disk budget

| | |
|---|---|
| Control-plane VM | 40 GiB dynamic VHDX on the Windows desktop |
| worker-1 (XPS 13) | 256 GB NVMe, LUKS: 70 GiB root (Longhorn), 158 GiB `/home`, 7.8 GiB unused swap |
| worker-2 (XPS 15) | 500 GB NVMe, LUKS: 70 GiB root (Longhorn), 378 GiB `/home`, 15.6 GiB unused swap |
| Backup SSD | 1 TB USB on worker-2, separate from the NVMe |

Kubelet image garbage collection and Longhorn share the 70 GiB root filesystem on each worker. Alert on root usage at 70% (warning) and 85% (critical) once Prometheus exists. Moving Longhorn to `/home`, or rebuilding the volume layout, would give it several times the space.

## Considered and not planned

| Service | Reason |
|---|---|
| Gitea | GitHub already provides Git, CI, and the public portfolio. Argo CD pulls from GitHub instead. |
| Self-hosted GitHub runner | Pull requests to a public repo could run code inside the lab. |
| HA control plane | Needs three control-plane nodes for etcd quorum; two is less reliable than one. The lab has one machine suited to running the control plane. |
| MinIO | The upstream repository is archived and gets no security fixes. Garage replaces it as the S3 backup target. |
| Velero, Falco | Good candidates for later: whole-namespace restores and runtime detection. Git and Argo CD already rebuild the Kubernetes objects; Secrets still need SOPS or Sealed Secrets. |
