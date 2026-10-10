# Architecture and Trust Boundaries

## Components

- **VM layer:** durable hostnames and IPs, time synchronization, storage attachment, firewalling, patching, and snapshots.
- **Kubernetes layer:** kubeadm control plane, worker scheduling, RBAC, namespaces, Secrets, and StatefulSets.
- **Network layer:** Cilium CNI, kube-proxy replacement, policy enforcement, and Hubble flow telemetry.
- **Security operations layer:** Wazuh managers, indexer, dashboard, endpoint agents, custom detections, and response runbooks.
- **External policy layer:** Project 07 policy-as-code remains in the Cloud Operations repository.

## Trust boundaries

1. The Kubernetes API is an administrative boundary; administrator kubeconfigs are secrets.
2. The Wazuh dashboard is an operator boundary; it should be private, TLS-protected, and independently authenticated.
3. Agent enrollment and event ingestion cross from monitored endpoints into the cluster; restrict their source networks and rotate enrollment secrets.
4. The indexer contains sensitive telemetry and must not be directly exposed.
5. CSI storage and VM snapshots contain security data and credentials; encrypt and control both.
6. Upstream manifests enter through a pinned staging boundary and must be reviewed before application.

## Availability limits

The reference topology is a lab, not a high-availability design. One control-plane VM is a control-plane and etcd failure domain. Local persistent volumes may bind data availability to one worker. The docs require evidence of restore and rescheduling behavior before making resilience claims.
