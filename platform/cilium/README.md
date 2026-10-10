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

## Sources

- [Cilium installation using kubeadm](https://docs.cilium.io/en/stable/installation/k8s-install-kubeadm/)
- [Kubernetes without kube-proxy](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)
