# Cilium Gateway API & Ingress Routing

Unified Layer 7 entrypoint for internal cluster services (`*.lab.internal`) using Cilium Gateway API and cert-manager TLS termination.

## Upstream Standards & Versioning

Kubernetes Gateway API replaces legacy Ingress with an expressive, role-oriented routing specification.

* **Upstream Specification:** The latest supported version is v1 as released by the [v1.6.1 release](https://github.com/kubernetes-sigs/gateway-api/releases/tag/v1.6.1) of this project.
* **Standard CRDs:** Pinned in `versions.env` (`GATEWAY_API_VERSION=v1.6.1`) and `scripts/Ansible/group_vars/k8s_cluster.yml` (`gateway_api_version: "v1.6.1"`).
* **Controller:** Cilium v1.20.2 native Gateway API controller (`gatewayAPI.enabled: true` in `platform/cilium/values.yaml`).

## Architecture

```text
Operator Client (*.lab.internal:443, resolving to the Gateway VIP on the home LAN)
                 │
                 ▼
[Cilium L2 Announcements] (a worker answers ARP for the VIP on Wi-Fi)
                 │
                 ▼
[Cilium Gateway API Listener] (:443 TLS termination with *.lab.internal cert)
        ├── / -> storage.lab.internal -> longhorn-frontend:80 (longhorn-system)
        └── / -> wazuh.lab.internal   -> wazuh-dashboard:5601 (wazuh)
```

The nodes sit directly on the home LAN, so clients reach the VIP with no host port forwarding. The Gateway pins `10.0.0.56`, the one address in the `lan-services` pool ([`../cilium/manifests/lb.yaml`](../cilium/manifests/lb.yaml)), which the router never assigns. Point `*.lab.internal` at it in the client's hosts file or DNS, and import the lab Root CA (`ca.crt` from Secret `cert-manager/lab-root-ca-keypair`) into the client's trust store.

**Access is limited to the admin desktop.** The only route is the Longhorn UI, which has no login, so `gateway-ingress` in [`../cilium/manifests/cluster.yaml`](../cilium/manifests/cluster.yaml) admits only `10.0.0.79/32`; other LAN hosts get `403`. Widen it only once every route has authentication. Windows `curl.exe` reports `CRYPT_E_NO_REVOCATION_CHECK` against this private CA, because the CA publishes no revocation list; browsers accept it, and `curl.exe --ssl-no-revoke` confirms the certificate itself is trusted.

Verified 2026-10-27: `https://storage.lab.internal` returns `200` with a trusted certificate from the desktop, and `403` from `worker-1`.

## Repeatable Deployment Pipeline

In this repository, installations are never executed via manual or ad-hoc CLI commands. Gateway API is deployed through a 100% repeatable pipeline:

1. **Version Pinning:** Pinned in `versions.env` and `group_vars/k8s_cluster.yml`.
2. **Declarative Values:** Gateway API enabled in `platform/cilium/values.yaml`.
3. **Automated Playbook:** `scripts/Ansible/gateway-api-setup.yaml`:
   - Fetches and applies the pinned `v1.6.1` standard-install CRDs.
   - Upgrades Cilium via `kubernetes.core.helm` with `gatewayAPI.enabled=true`.
   - Waits for the `cilium` `GatewayClass` to transition to condition `Accepted=True`.
   - Stages and applies the Gateway listener and Wildcard Certificate.
   - Deploys the HTTPRoutes.

## Validation

```bash
# Verify Gateway API CRDs are installed
kubectl get crd | grep gateway.networking.k8s.io

# Verify Cilium GatewayClass is accepted
kubectl get gatewayclass cilium

# Verify Gateway status and assigned IP
kubectl get gateway -A

# Verify HTTPRoutes
kubectl get httproute -A
```
