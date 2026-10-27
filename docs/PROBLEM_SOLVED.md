# Operational Case Study: Kubernetes SecOps Platform Deployment & Troubleshooting

This document records the architectural challenges, root-cause analyses, and resolutions encountered while deploying a multi-node Kubernetes SecOps platform running Cilium (eBPF) and upstream Wazuh v4.14.8. Incidents 1 to 6 happened on the original KVM/libvirt virtual machines; Incidents 7 to 9 happened while rebuilding the lab as a hybrid cluster.

---

## Architecture Summary

### Current hybrid cluster (from 2026-10-26)

* **Control plane:** `control-plane-1`, a Hyper-V Generation 2 VM on a Windows 11 desktop, bridged onto the home LAN (2 vCPU, 8 GiB RAM, 40 GiB disk)
* **Workers:** `worker-1` (Dell XPS 13 9360, 8 threads, 8 GiB) and `worker-2` (Dell XPS 15 9510, 16 threads, 32 GiB), bare metal on Wi-Fi with LUKS-encrypted disks
* **OS:** Rocky Linux 10.2 on every node, SELinux enforcing with containerd container labeling
* **Kubernetes, CNI:** unchanged versions, below; every node has its own LAN address with no NAT between nodes

### Original libvirt build (Incidents 1 to 6)

* **Hypervisor / Host:** KVM / libvirt on Ubuntu 24.04 (`10.0.0.39`)
* **Cluster Nodes:**
  * `control-plane-1` (`192.168.100.10`, 2 vCPU, 4 GiB RAM, 60 GiB disk)
  * `worker-1` (`192.168.100.21`, 4 vCPU, 8 GiB RAM, 60 GiB disk)
  * `worker-2` (`192.168.100.22`, 4 vCPU, 8 GiB RAM, 60 GiB disk)
  * `worker-3` (`192.168.100.23`, 4 vCPU, 8 GiB RAM, 90 GiB disk)
* **Kubernetes Version:** `v1.37.1` (bootstrapped with `kubeadm`, `containerd` with `SystemdCgroup=true`)
* **CNI:** Cilium `v1.20.2` (eBPF kube-proxy replacement, Hubble UI enabled)
* **Storage:** Longhorn `v1.12.1` (distributed, replicated block storage as default StorageClass) + Rancher `local-path-provisioner` (`v0.0.37`) as local fallback
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

## Incident 6: Zero-Trust Cluster Default-Deny Blocks Distributed CSI Storage Engine (Longhorn)

### Symptom
After scaling the cluster to three worker nodes and installing Longhorn via Helm, the deployment hung indefinitely at `TASK [Deploy or upgrade Longhorn via Helm]` with `wait: true`:
1. `longhorn-manager` pods were stuck at `1/2 Running` with readiness probe failing on `https://:9502/v1/healthz` (`dial tcp: connect: connection refused`).
2. `longhorn-driver-deployer` was blocked in `Init:0/1` waiting on the manager.
3. `longhorn-ui` crashed repeatedly in `CrashLoopBackOff`:
   ```text
   nginx: [emerg] host not found in upstream "longhorn-backend" in /var/config/nginx/nginx.conf:34
   ```

### Root Cause Analysis
1. **API Server Timeout in Pod Logs:** Inspecting `longhorn-manager` container logs revealed repeated 30-second timeouts trying to acquire the leader election lease lock:
   ```text
   leaderelection.go:461] "Error retrieving lease lock" err="Get \"https://10.96.0.1:443/apis/coordination.k8s.io/v1/namespaces/longhorn-system/leases/longhorn-manager-webhook-lock\": dial tcp 10.96.0.1:443: i/o timeout"
   ```
2. **Node-Level Network was Healthy:** Direct testing from `worker-3` proved host networking was fully operational:
   * ICMP ping to control plane: `0.38 ms` (0% loss)
   * Direct TCP socket to `192.168.100.10:6443`: `OPEN`
   * ClusterIP socket to `10.96.0.1:443`: `OPEN`
   * Host firewall: `sudo ufw status` $\rightarrow$ `inactive`
3. **Cilium eBPF Default-Deny Dropping Pod Traffic:** Because the cluster enforces a Zero-Trust baseline ([`platform/cilium/cluster-default-deny.yaml`](../platform/cilium/manifests/cluster.yaml) (now `manifests/cluster.yaml`)), every new namespace defaults to dropping all ingress and egress packets. The newly created `longhorn-system` namespace had no allow rules. Cilium's eBPF datapath dropped the pods' outbound SYN packets to `10.96.0.1:443` and dropped CoreDNS queries to `kube-dns:53`.

```text
longhorn-manager (pod: 10.244.3.73)
       │
       ▼ (Egress to 10.96.0.1:443)
[ Cilium eBPF Datapath ]
       │
       ▼ (No CiliumNetworkPolicy for longhorn-system)
   ❌ DROPPED (CiliumClusterwideNetworkPolicy: default-deny)
       │
       ▼
Result: i/o timeout -> Lease lock fails -> Port 9502 never opens -> Kubelet reports connection refused!
```

### Resolution
1. Authored a custom zero-trust policy in [`platform/cilium/longhorn-allow.yaml`](../platform/cilium/manifests/longhorn.yaml) (now `manifests/longhorn.yaml`) scoped to `namespace: longhorn-system`:
   * **API Server Egress:** Allowed `toEntities: [kube-apiserver]` on ports `6443` and `443` for lease management and CRD sync.
   * **CoreDNS Egress:** Allowed `toEndpoints` matching `k8s-app: kube-dns` in `kube-system` on port `53/ANY`.
   * **Internal Pod Mesh:** Allowed full ingress/egress among pods in `longhorn-system` for manager-to-webhook API and replica data synchronization.
   * **Node & Host Communication:** Allowed `fromEntities: [host, remote-node]` and `toEntities: [host, remote-node]` for Kubelet `/v1/healthz` probes and node-local iSCSI attachments (`iscsid`).
2. Applied the policy to the cluster:
   ```bash
   kubectl apply -f platform/cilium/longhorn-allow.yaml
   ```
3. **Verification:** The instant Cilium loaded the eBPF policy into the kernel:
   * `longhorn-manager` acquired the lease lock and transitioned to `2/2 Running`.
   * `longhorn-driver-deployer` completed initialization (`1/1 Running`).
   * `longhorn-ui` resolved upstream DNS and stabilized (`1/1 Running`).
   * All 27 storage pods across all 3 nodes stabilized in `Running` state.
   * `longhorn` registered as the cluster's default dynamic StorageClass with live volume expansion enabled:
     ```text
     NAME                 PROVISIONER          RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION
     local-path           rancher.io/local-path Delete          WaitForFirstConsumer false
     longhorn (default)   driver.longhorn.io   Delete          Immediate           true
     ```

### Follow-up
* In a zero-trust cluster, new infrastructure namespaces (storage, observability, service mesh) *must* have their baseline network policies staged and applied alongside Helm deployments.
* When a pod's readiness probe reports `connection refused` on an admission webhook port, check the container logs for blocked upstream dependencies (e.g. API server leases) before assuming a container binary or port crash.

---

## Incident 7: SELinux Denies the Control Plane Its Own Keys

### Symptom
The first `kubeadm init` on the hybrid cluster failed after about 100 seconds:

```text
error execution phase wait-control-plane: could not bootstrap the admin user in file admin.conf:
  dial tcp <control-plane>:6443: connect: connection refused
```

Certificates, kubeconfigs, and static Pod manifests had all been written. The kubelet log showed etcd, kube-apiserver, kube-controller-manager, and kube-scheduler all in `CrashLoopBackOff` at the same time.

### Root Cause Analysis
1. When every control-plane component fails together, the cause is usually something they share. The containerd and kubelet cgroup drivers matched (`SystemdCgroup = true`, `cgroupDriver: systemd`), so the runtime configuration was ruled out.
2. `ausearch -m avc` showed the denials:

   ```text
   avc: denied { read } for comm="kube-apiserver" name="sa.key"
     scontext=system_u:system_r:container_t:s0:c447,c900
     tcontext=unconfined_u:object_r:kubernetes_file_t:s0 tclass=file
   ```

3. The rebuild turned on containerd's `enable_selinux`, so containers run as `container_t`. The `container-selinux` policy labels `/etc/kubernetes` as `kubernetes_file_t`, which `container_t` may not read. Every static pod failed to open its keys and kubeconfigs (`EACCES`) and exited.
4. The libvirt build had never run with container labeling, so this combination had not been tested before.

### Resolution
The options were relabeling `/etc/kubernetes` as `container_file_t` (any container mounting it could then read the cluster CA key), switching SELinux to permissive (as the upstream kubeadm guide suggests), or scoping an exception. The fix scopes it: `kubeadm-bootstrap.yaml` writes one kubeadm patch per control-plane component to `/etc/kubernetes/patches`:

```yaml
spec:
  securityContext:
    seLinuxOptions:
      type: spc_t
```

and the kubeadm configuration points `patches.directory` at that folder.

### Verification
```bash
ps -eZ | grep -E 'kube-apiserver|etcd'
# system_u:system_r:spc_t:s0:... kube-apiserver
# system_u:system_r:spc_t:s0:... etcd
```

Only the four control-plane pods report `spc_t`; every other pod runs as the default `container_t`.

---

## Incident 8: A Re-run Would Have Skipped the Failed Init

### Symptom
After Incident 7, re-running `site.yaml` would have reported the init task as already done.

### Root Cause Analysis
The init task used `creates: /etc/kubernetes/admin.conf`. kubeadm writes `admin.conf` during the kubeconfig phase, before the control plane starts, so a failed init leaves it behind. The guard treated "the file exists" as "init succeeded", and later plays would have run against a control plane that was not serving.

### Resolution
The playbook now checks the API server instead of a file:

1. `kubectl get --raw=/readyz` with the admin kubeconfig. If it succeeds, init is skipped.
2. If it fails and `admin.conf` does not exist, init runs.
3. If it fails but `admin.conf` exists, the play stops with instructions to fix the cause and run `kubeadm reset -f`.

### Verification
The next run stopped at the new guard, as intended. After `kubeadm reset -f`, init succeeded and both workers joined.

---

## Incident 9: Helm Disappears Under `sudo`

### Symptom
`helm-install.yaml` failed at its version check with `rc=2` and empty stdout and stderr, although `/usr/local/bin/helm version` worked for the `kubeadmin` user.

### Root Cause Analysis
Ansible runs these tasks through `sudo`. Rocky Linux's sudoers `secure_path` does not include `/usr/local/bin`, so root could not find `helm` by name and the command module reported "Error executing command". The cloud image used on the libvirt build had not exposed this. Every `kubernetes.core.helm` task would have failed the same way.

### Resolution
A single variable in `group_vars/k8s_cluster.yml`, `helm_binary: /usr/local/bin/helm`, is used by the install destination, both version checks, and `binary_path` on every Helm module call. Loosening `secure_path` was rejected because it is deliberate hardening.

### Verification
`site.yaml` completed with no failures; Cilium installed through Helm, and all three nodes reported `Ready`.

---

## Key Takeaways & Interview Talking Points

1. **Kustomize Over Vendor Invasiveness:** Declarative overlays allow tailoring third-party Helm/manifest charts to bare-metal infrastructure without maintaining custom vendor forks.
2. **Storage Topology Awareness:** `local-path` is hostPath-based; volume affinity strictly binds pods to specific worker nodes. Storage constraints directly impact the Kubernetes scheduling pipeline.
3. **Host-Level Kubelet Protections:** Kubelet acts as a node watchdog. Understanding eviction thresholds (`imageGCHighThresholdPercent`) and conditions (`DiskPressure`, `MemoryPressure`) is essential for root-causing scheduling freezes.
4. **Day 2 Live Operations vs. IaC:** Destructive Terraform replacements must never be applied blindly to stateful production nodes. Live hypervisor block resizing (`virsh blockresize` + `growpart`) followed by IaC state reconciliation is the industry-standard workflow.
5. **Observed-Flow Policies Have Blind Spots:** Allow rules written from captured traffic only cover what happened during the capture. Long-lived connections hide reconnect-time lookups until a failure forces them, so test policy changes with deliberate restarts.
6. **Zero-Trust Network Boundaries Demand Day-0 Provisioning:** When running cluster-wide default-deny (`CiliumClusterwideNetworkPolicy`), third-party helm installations with `wait: true` will fail silently if pod-to-API and DNS egress policies are omitted. Isolate node vs pod reachability to pinpoint eBPF policy drops.
7. **Scope SELinux Exceptions Instead of Disabling It:** An AVC denial names the process, its label, and the file's label. Fixing it for exactly the components that need it (`spc_t` on four static pods) keeps every workload confined.
8. **Idempotency Guards Must Test the Outcome:** A marker file written partway through a step does not prove the step finished. Check the state that matters, such as a serving API, and fail loudly on partial state.
9. **Privilege Changes the Environment:** `sudo` replaces `PATH` with `secure_path`. Use full paths for binaries installed outside the distribution's directories.
