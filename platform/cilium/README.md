# Cilium Networking and Observability

Cilium is the cluster CNI and replaces kube-proxy for this lab. The Helm values enable Hubble for flow visibility and keep routing conservative for a small VM network.

## Install

Load the reviewed version:

```bash
set -a
. ../../versions.env
set +a
helm install cilium oci://quay.io/cilium/charts/cilium \
  --version "${CILIUM_VERSION}" \
  --namespace kube-system \
  --values platform/cilium/values.yaml \
  --set k8sServiceHost=k8s-api.lab.internal \
  --set k8sServicePort=6443
```

The control plane must have been initialized with `--skip-phases addon/kube-proxy`. The API hostname must resolve from every node before Cilium starts.

## Validate

```bash
cilium status --wait
cilium connectivity test
kubectl -n kube-system exec ds/cilium -- \
  cilium-dbg status --verbose
```

Confirm that `KubeProxyReplacement` is enabled. Inspect dropped flows before adding allow policies:

```bash
cilium hubble port-forward &
hubble observe --verdict DROPPED --follow
```

## Apply boundaries

Create the namespace and baseline after Cilium is healthy:

```bash
kubectl apply -f platform/manifests/secops-namespace.yaml
kubectl apply -f platform/cilium/secops-default-deny.yaml
kubectl apply -f platform/cilium/secops-dns-egress.yaml
```

The default deny activates isolation. It does not make Wazuh functional by itself. Add narrowly scoped allow rules after the upstream Wazuh workload labels and service ports have been verified in the staged release.

## Known drops

Hubble shows these drops after the baseline policies are applied. None of them break a component.

### IPv6 neighbor discovery (expected)

The cluster is IPv4-only, so Cilium drops ICMPv6 Router Solicitation, Neighbor Solicitation, and MLD (`ICMPv6 143`) from every pod as `Unsupported L3 protocol`. Policy has no effect on these drops.

### Hubble relay gRPC service-config lookup (open decision)

Observed on 2026-10-21 during a deliberate restart of `hubble-relay`, and not in steady-state flows:

```text
kube-system/hubble-relay -> kube-system/coredns:53 dns-request proxy DROPPED
  (DNS Query _grpc_config.hubble-peer.kube-system.svc.cluster.local. TXT)
```

At startup, the relay's gRPC client looks for an optional service-config TXT record. The relay's DNS rule in `kube-system-allow.yaml` allows `*.kube-system.svc.cluster.local`. In Cilium, `*` matches a single DNS label, so the two extra labels (`_grpc_config.hubble-peer`) fall outside it. gRPC treats the failed lookup as "no service config", and the relay starts normally.

| Option | Change | Tradeoff |
| :--- | :--- | :--- |
| **A. Allow exactly** | Add `matchName: "_grpc_config.hubble-peer.kube-system.svc.cluster.local"` to the hubble-relay DNS rule | Removes restart noise from Hubble; one more allowed name to keep current |
| **B. Leave denied** | Add a comment to the rule explaining the drop | Smallest policy; the drop reappears on every relay restart and must be recognized as harmless |

**Decision:** not yet made.

To check either option, restart the relay and look for drops in the Cilium agent on the relay's node (an agent only sees its own node's flows):

```bash
kubectl -n kube-system rollout restart deploy/hubble-relay
kubectl -n kube-system rollout status deploy/hubble-relay
node=$(kubectl -n kube-system get pod -l k8s-app=hubble-relay \
  -o jsonpath='{.items[0].spec.nodeName}')
agent=$(kubectl -n kube-system get pod -l k8s-app=cilium \
  --field-selector spec.nodeName="$node" -o name)
kubectl -n kube-system exec "$agent" -c cilium-agent -- \
  hubble observe --verdict DROPPED --since 2m -o compact
```

## Sources

- [Cilium installation using kubeadm](https://docs.cilium.io/en/stable/installation/k8s-install-kubeadm/)
- [Kubernetes without kube-proxy](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)
