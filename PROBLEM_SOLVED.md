# Operational Case Study: Kubernetes SecOps Platform Deployment & Troubleshooting

This document records the architectural challenges, root-cause analyses, and resolutions encountered while deploying a multi-node Kubernetes SecOps platform running Cilium (eBPF) and upstream Wazuh v4.14.8 on KVM/libvirt virtual machines.

---

## Architecture Summary

* **Hypervisor / Host:** KVM / libvirt on Ubuntu 24.04 (`10.0.0.39`)
* **Cluster Nodes:**
  * `control-plane-1` (`192.168.100.10`, 2 vCPU, 4 GiB RAM, 60 GiB disk)
  * `worker-1` (`192.168.100.21`, 4 vCPU, 8 GiB RAM, 60 GiB disk)
  * `worker-2` (`192.168.100.22`, 4 vCPU, 8 GiB RAM, 60 GiB disk)
* **Kubernetes Version:** `v1.37.1` (bootstrapped with `kubeadm`, `containerd` with `SystemdCgroup=true`)
* **CNI:** Cilium `v1.20.2` (eBPF kube-proxy replacement, Hubble UI enabled)
* **Storage:** Rancher `local-path-provisioner` (`v0.0.37`) providing dynamic hostPath storage
* **Workload:** Upstream Wazuh `v4.14.8` (Indexer, Dashboard, Manager Master, Manager Worker)

---

## Incident 1: Upstream Vendor StorageClass Name Mismatch

### Symptom
When deploying the upstream Wazuh overlay (`envs/local-env/`), persistent volume claims (PVCs) for the StatefulSets remained in `Pending` state.

### Root Cause
1. Upstream Wazuh StatefulSet manifests explicitly request a StorageClass named `wazuh-storage`.
2. In the upstream `envs/local-env/storage-class.yaml`, the default provisioner was hardcoded to `microk8s.io/hostpath`.
3. Our bare-metal cluster does not run MicroK8s; dynamic storage is provided by Rancher's `rancher.io/local-path` driver under the default class `local-path`.

```text
Wazuh StatefulSet ("I demand wazuh-storage!")
                   │
                   ▼
       StorageClass "wazuh-storage"
                   │
                   ▼ (Mismatch!)
    provisioner: microk8s.io/hostpath  ❌ (Driver not present)
```

### Resolution
Patched `.cache/wazuh-kubernetes-v4.14.8/envs/local-env/storage-class.yaml` using Kustomize:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: wazuh-storage
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
```
* **Why `volumeBindingMode: WaitForFirstConsumer` matters:** Delays volume binding until a pod is scheduled, ensuring the PV directory is allocated on the exact worker node where the pod has compute placement.

---

## Incident 2: Dual-Stack DNS & IPv6 Handshake Timeouts (`ErrImagePull`)

### Symptom
During initial container pull on `worker-1`, `wazuh-indexer-0` entered `ErrImagePull` and `ImagePullBackOff`.

### Root Cause Analysis
Running `kubectl describe pod wazuh-indexer-0 -n wazuh` revealed:
```text
dial tcp [2600:1f18:2148:bc02:42ea:bd9f:c9ca:2a1f]:443: connect: network is unreachable
Get "https://production.cloudfront.docker.com/...": net/http: TLS handshake timeout
```
1. **Network Topology:** The libvirt virtual network bridge (`virbr-k8s`) is an IPv4-only subnet (`192.168.100.0/24`) with no IPv6 gateway.
2. **Dual-Stack DNS:** When `worker-1` queried Docker Hub and CloudFront CDN for blob downloads, DNS returned both IPv4 (`A`) and IPv6 (`AAAA`) records.
3. **Go Runtime Dialer:** `containerd`'s HTTP client attempted connections against IPv6 endpoints first. Because no default IPv6 route existed, connections hung until the 30-second TLS handshake timeout expired before falling back to IPv4.

### Resolution
* Traced the failure via Kubelet event streams.
* Kubernetes exponential backoff (`ImagePullBackOff`) eventually retried over IPv4.
* Reclaiming layer caches: Deleting the StatefulSet pod (`kubectl delete pod wazuh-indexer-0 -n wazuh`) reset the 5-minute backoff counter to 0 while preserving already-downloaded layers in containerd's content store, allowing the pull to complete cleanly.

---

## Incident 3: Kubelet `DiskPressure` & The Pod Eviction Storm

### Symptom
`wazuh-manager-worker-0` and `wazuh-manager-master-0` entered a rapid eviction loop:
```text
wazuh-manager-worker-0   0/1   Evicted   0   0s
wazuh-manager-worker-0   0/1   Pending   0   0s
wazuh-manager-master-0   0/1   Evicted   0   0s
```
Scheduler events reported:
```text
0/3 nodes are available:
  1 node(s) didn't match PersistentVolume's node affinity,
  2 node(s) had untolerated taint(s).
```

### Root Cause Analysis
1. **Kubelet Taint:** `worker-2` had the taint `node.kubernetes.io/disk-pressure:NoSchedule` (`DiskPressure: True`).
2. **Local Storage Affinity:** `wazuh-manager-master-0` had its persistent disk dynamically bound on `worker-2`. It could not run on `worker-1` (node affinity mismatch) and could not run on `control-plane-1` (control-plane taint).
3. **Capacity Math:**
   * Disk allocation in Terraform was initially **30 GiB**.
   * On first boot, Wazuh Manager Master downloaded and indexed complete vulnerability databases (NVD, Debian, Ubuntu, Red Hat CVE feeds), consuming **8.3 GiB** in `/opt/local-path-provisioner/`.
   * Combined with containerd images (**5.6 GiB**) and base OS (**5 GiB**), disk usage crossed Kubelet's **85%** `imageGCHighThresholdPercent` threshold.
   * Kubelet aggressively evicted pods to prevent kernel panics; the StatefulSet controller repeatedly recreated them, creating an infinite loop.

```text
30 GiB Virtual Disk Breakdown (worker-2):
┌────────────────┬───────────────┬─────────────────┬──────────┐
│ OS Base (5 GiB)│ Images (6 GiB)│ Wazuh DB (8 GiB)│ Free 7G  │
└────────────────┴───────────────┴─────────────────┴──────────┘
                                                   ▲
                              Spikes > 85% ────────┘ -> DiskPressure Triggered!
```

### Resolution: Live, Zero-Downtime Disk Expansion
Instead of shrinking workloads, we expanded the infrastructure to production sizing (**60 GiB**):

1. **Live Block Resize on Hypervisor (Zero Downtime):**
   ```bash
   virsh -c qemu:///system blockresize worker-2 vda 60G
   virsh -c qemu:///system blockresize worker-1 vda 60G
   ```
2. **Online Filesystem Expansion (Inside Guests):**
   ```bash
   sudo growpart /dev/vda 1
   sudo resize2fs /dev/vda1
   sudo systemctl restart kubelet
   ```
   * Result: `worker-2` disk usage dropped from **86%** down to **30%** (41 GiB free).
   * Kubelet automatically cleared `DiskPressure: False` and removed the taint.
3. **IaC Reconciliation:**
   Updated `terraform/storage.tf` to `capacity = 60 GiB` to prevent configuration drift.
4. **Cleanup:**
   ```bash
   kubectl delete pods -n wazuh --field-selector status.phase=Failed
   ```

---

## Incident 4: Microservice Cold-Boot & API Handshake Timeout

### Symptom
Browser access to `https://localhost:8443` loaded OpenSearch Dashboards, but navigating to `/app/wz-home` presented:
```text
AxiosError: timeout of 20000ms exceeded
  at WzAuthentication.login
```

### Root Cause Analysis
1. The user entered valid credentials (`admin` / `SecretPassword`), successfully authenticating into OpenSearch Dashboards.
2. The Wazuh Dashboard plugin attempted to establish an internal HTTPS session with the backend Wazuh Manager REST API (`wazuh-manager-master-0`).
3. Because `wazuh-manager-master-0` had just restarted following the disk expansion, its Python REST API daemon (`wazuh-apid`) was still completing database migrations and startup routines (cold boot took ~2 minutes).
4. The dashboard's frontend Axios HTTP client hit its default 20-second timeout.

### Verification & Resolution
Inspecting `kubectl logs -n wazuh -l app=wazuh-dashboard --tail=50` revealed the exact transition:
```text
POST /api/login                                        200  7931ms
PUT  /api/saved_objects/index-pattern/wazuh-alerts-*   200  365ms
POST /internal/search/opensearch                       200  48ms
POST /api/request                                      200  206ms
```
Once `wazuh-apid` initialized, all subsequent API requests returned **`HTTP 200 OK`** within ~200ms. A browser refresh loaded the full Wazuh SecOps console cleanly.

---

## Incident 5: Power Loss Exposes an Untested DNS Rule (Agent `Invalid ID`)

### Symptom
After the KVM host lost power and rebooted, all three VMs and every Wazuh pod returned to `Running`. A new agent (`wsl-desktop`, WSL on the LAN at `10.0.0.79`) enrolled successfully through the master on `10.0.0.241:1515`, but never appeared as active. The worker manager rejected every event connection:
```text
wazuh-remoted: WARNING: (1408): Invalid ID 001 for the source ip: '10.0.0.79' (name 'unknown').
```

### Root Cause Analysis
1. **Split cluster:** `cluster_control -l` on the master listed only the master. The master issued agent key `001`, but with no worker connected it could not replicate the key, so the worker treated the agent as unknown.
2. **Worker could not resolve the master:** The worker's `cluster.log` showed healthy keepalives until the outage (16:48 UTC), then:
   ```text
   ERROR: [Local Server] [Main] Could not connect to master: [Errno -2] Name or service not known.
   ```
3. **Cilium dropped the lookup:** Hubble showed the DNS proxy rejecting the query:
   ```text
   wazuh/wazuh-manager-worker-0 -> kube-system/coredns:53 dns-request proxy DROPPED
     (DNS Query wazuh-manager-master-0.wazuh-cluster.wazuh. A)
   ```
   `allow-cluster-dns` permitted only `*.wazuh.svc.cluster.local` and `*.wazuh-cluster.wazuh.svc.cluster.local`. In Cilium `matchPattern`, `*` never crosses a dot, so neither the configured name `wazuh-manager-master-0.wazuh-cluster.wazuh` nor the search-path expansion the resolver tries first matched.
4. **Why it had worked:** The worker's connection to the master predated the policy. Cilium does not tear down established flows, so the cluster kept running. The DNS lookup only happens on reconnect, so it never appeared in the Hubble flows the allow rules were written from. The power loss forced the first reconnect.

### Resolution
1. Added explicit patterns for the configured name and its search-path expansions to `platform/cilium/wazuh-dns-egress.yaml`:
   ```yaml
   - matchPattern: "*.wazuh-cluster.wazuh"
   - matchPattern: "*.wazuh-cluster.wazuh.wazuh.svc.cluster.local"
   - matchPattern: "*.wazuh-cluster.wazuh.cluster.local"
   ```
2. Applied the policy; the worker rejoined on its next 10-second retry without a restart:
   ```text
   NAME                    TYPE    VERSION  ADDRESS
   wazuh-manager-master    master  4.14.8   wazuh-manager-master-0.wazuh-cluster.wazuh
   wazuh-manager-worker-0  worker  4.14.8   10.244.1.163
   ```
3. Restarted the agent. `wsl-desktop` became active and alerts began arriving in the dashboard.
4. Marked all three VMs for `virsh autostart` so they return after the next power loss.

### Follow-up
* Pod `Running` status did not reveal the split cluster. Monitor that `cluster_control -l` lists every manager node.
* Policies built from observed flows miss traffic that only occurs on restart. Restart each component deliberately after a policy change and watch Hubble for drops.

---

## Key Takeaways & Interview Talking Points

1. **Kustomize Over Vendor Invasiveness:** Declarative overlays allow tailoring third-party Helm/manifest charts to bare-metal infrastructure without maintaining custom vendor forks.
2. **Storage Topology Awareness:** `local-path` is hostPath-based; volume affinity strictly binds pods to specific worker nodes. Storage constraints directly impact the Kubernetes scheduling pipeline.
3. **Host-Level Kubelet Protections:** Kubelet acts as a node watchdog. Understanding eviction thresholds (`imageGCHighThresholdPercent`) and conditions (`DiskPressure`, `MemoryPressure`) is essential for root-causing scheduling freezes.
4. **Day 2 Live Operations vs. IaC:** Destructive Terraform replacements must never be applied blindly to stateful production nodes. Live hypervisor block resizing (`virsh blockresize` + `growpart`) followed by IaC state reconciliation is the industry-standard workflow.
5. **Observed-Flow Policies Have Blind Spots:** Allow rules written from captured traffic only cover what happened during the capture. Long-lived connections hide reconnect-time lookups until a failure forces them, so test policy changes with deliberate restarts.
