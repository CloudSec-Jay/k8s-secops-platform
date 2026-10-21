# Cluster Roadmap

Services planned for the lab, in build order. Each one ships in its own branch and pull request, with its Cilium policy, a deliberate restart test, and an update to the project site.

Memory figures are lab-sized estimates. Measure before and after each addition with `free -h` on the host and `kubectl top nodes` / `kubectl top pods -A` in the cluster.

## Rules for every addition

- **Policy first.** The cluster is default-deny. Write the Cilium allow rules with the service, then restart it on purpose and watch Hubble for drops. Rules written only from observed flows miss reconnect-time traffic (see INC-05 in [`PROBLEM_SOLVED.md`](PROBLEM_SOLVED.md)).
- **Pin versions** in `versions.env`.
- **Read the Terraform plan's destroy lines** before applying anything.
- **Set memory limits** on every workload.

## Phase 1: Platform

| Service | Purpose | Approx. RAM | Notes |
|---|---|---|---|
| worker-3 | Third worker VM (4 vCPU, 8 GiB) | up to 8 GB on the host | The first plan replaced the lab network and existing cloud-init disks. Resolve that before applying. |
| metrics-server | Enables `kubectl top` | ~50 MB | Needed to measure everything below |
| Longhorn | Replicated block storage across workers | 1–1.5 GB | Dedicated data disk per worker. Replicas protect against VM failure, not host disk failure. |
| Pod anti-affinity | Keep the Wazuh master and worker managers on different nodes | – | Easier once Longhorn removes node-pinned volumes |
| Kyverno | Admission policy: block or fix unsafe workloads | 300–600 MB | Audit mode first, then enforce. Document why Kyverno here while the portfolio uses OPA elsewhere. |

## Phase 2: GitOps

| Service | Purpose | Approx. RAM | Notes |
|---|---|---|---|
| Argo CD | Deploy the cluster from this GitHub repo | 0.5–1 GB | Pulls from GitHub over outbound connections only; nothing exposed. Everything after this phase deploys through it. |

## Phase 3: Access

| Service | Purpose | Approx. RAM | Notes |
|---|---|---|---|
| cert-manager + private CA | Issue certificates for every app | ~200 MB | Own `.internal` domain; install the root CA once on each device |
| AdGuard Home | Local DNS for the `.internal` domain | ~100 MB | Also blocks ads on the home network |
| Cilium Gateway API | One LAN address, apps routed by hostname | ~100 MB | Built into Cilium; no separate ingress controller |

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

## Memory budget

| | |
|---|---|
| Host RAM | 32 GB, about 16 GB free before worker-3 |
| Worker capacity | 16 GB now, 24 GB with worker-3 |
| New workloads (all phases) | about 7–10 GB |

The Wazuh indexer and Prometheus are the largest consumers. After worker-3, the host has no room for another VM.

## Considered and not planned

| Service | Reason |
|---|---|
| Gitea | GitHub already provides Git, CI, and the public portfolio. Argo CD pulls from GitHub instead. |
| Self-hosted GitHub runner | Pull requests to a public repo could run code inside the lab. |
| HA control plane | Needs three control-plane nodes for etcd quorum; two is less reliable than one. Not enough host RAM alongside worker-3. |
| MinIO + Velero, Falco | Good candidates for later: off-host backups and runtime detection. |
