# Cilium Networking and Observability

Cilium is the cluster CNI and replaces kube-proxy for this lab. The Helm values enable Hubble for flow visibility, L2 announcements for LoadBalancer addresses on the home LAN, and the Gateway API controller.

## Install

[`scripts/Ansible/cilium-install.yaml`](../../scripts/Ansible/cilium-install.yaml) installs the pinned chart (`cilium_version` in `group_vars/k8s_cluster.yml`, matching `CILIUM_VERSION` in [`versions.env`](../../versions.env)) with [`values.yaml`](values.yaml). It runs as the last step of `site.yaml`:

```bash
cd scripts/Ansible
ansible-playbook cilium-install.yaml -K
```

The playbook installs the Gateway API CRDs first, because the operator only starts its Gateway controller if they exist. Because kube-proxy is replaced, Cilium cannot reach the API server through its Service address. The playbook sets `k8sServiceHost` to the control-plane address from the inventory. The control plane must have been initialized with the kube-proxy add-on skipped.

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

Policies live in [`manifests/`](manifests/), one file per namespace or concern:

| File | Contents |
|---|---|
| `cluster.yaml` | Cluster-wide `default-deny` baseline, plus allows for Cilium health checks and Gateway API ingress |
| `kube-system.yaml` | CoreDNS, Hubble relay and UI, Metrics Server |
| `cert-manager.yaml`, `longhorn.yaml`, `wazuh.yaml` | Allow rules for each component's namespace |
| `argocd.yaml` | Argo CD allow rules (in progress) |
| `lb.yaml` | LoadBalancer IP pool and L2 announcement policy |

`default-deny` in `cluster.yaml` is the single baseline: it denies all traffic in every namespace, including ones created later, so no namespace needs its own default deny. Apply each component's allow policy before its workload, then the baseline last after Cilium is healthy:

```bash
kubectl apply -f platform/cilium/manifests/kube-system.yaml
kubectl apply -f platform/cilium/manifests/cluster.yaml
```

Check DNS before applying `kube-system.yaml`. CoreDNS forwards to each node's `/etc/resolv.conf`, which `node-network.yaml` pins to the home router, and the CoreDNS policy allows only that address. If a node still lists other resolvers, run `node-network.yaml` and restart CoreDNS first (`kubectl -n kube-system rollout restart deploy/coredns`), or cluster DNS stops resolving external names.

The default deny activates isolation. It does not make Wazuh functional by itself. Add narrowly scoped allow rules after the upstream Wazuh workload labels and service ports have been verified in the staged release.

Argo CD is planned to sync this folder (`platform/argocd/apps/cilium-policies.yaml`). Until then, apply it by hand.

## LAN exposure

All nodes sit directly on the home LAN, so no host port forwarding is involved. A Service labelled `lab.internal/expose: lan` gets an address from the `lan-services` pool in `lb.yaml`, and one worker answers ARP for it on Wi-Fi (`interfaces: ^wlp`). The control plane is excluded from announcing.

The pool must hold only addresses the router never hands out by DHCP. It currently holds one, `10.0.0.56`, which the Gateway pins. Services that need their own LAN ports later (Wazuh agent enrollment and events) can share that address with the `lbipam.cilium.io/sharing-key` annotation as long as their ports differ. Over Wi-Fi, test failover by powering off the lease holder and timing how long the address takes to answer again.

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

At startup, the relay's gRPC client looks for an optional service-config TXT record. The relay's DNS rule in `manifests/kube-system.yaml` allows `*.kube-system.svc.cluster.local`. In Cilium, `*` matches a single DNS label, so the two extra labels (`_grpc_config.hubble-peer`) fall outside it. gRPC treats the failed lookup as "no service config", and the relay starts normally.

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
