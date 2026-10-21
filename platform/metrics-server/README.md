# Metrics Server

Metrics Server supplies the Kubernetes resource metrics API used by
`kubectl top` and Horizontal Pod Autoscalers. This deployment verifies TLS in
both directions and does not use `--kubelet-insecure-tls`.

## 1. Request kubelet serving certificates

The kubeadm template enables `serverTLSBootstrap` for future clusters. Enable
the same setting on the running nodes with a rolling kubelet restart:

```bash
cd scripts/Ansible
ansible-playbook -i k8s.ini kubelet-serving-certificates.yaml
```

Kubernetes does not automatically approve kubelet serving certificates. List
the pending requests from a host with an administrator kubeconfig:

```bash
kubectl get csr
```

For each CSR whose signer is `kubernetes.io/kubelet-serving`, inspect the
embedded request:

```bash
kubectl get csr <csr-name> -o yaml
kubectl get csr <csr-name> -o jsonpath='{.spec.request}' \
  | base64 --decode \
  | openssl req -noout -text
```

Before approval, confirm all of these facts:

- `spec.username` is `system:node:<node-name>`.
- `spec.groups` contains `system:nodes`.
- Usages are limited to serving-certificate usages.
- Every DNS name and IP subject alternative name belongs to that node.

Approve only the CSR that was just verified:

```bash
kubectl certificate approve <csr-name>
```

Repeat the inspection separately for every node. Do not bulk-approve requests.

## 2. Install Metrics Server

The install playbook stops if any node is still missing its approved serving
certificate. It then applies the Cilium allow policy before creating the pod
and installs the pinned Helm chart:

```bash
cd scripts/Ansible
ansible-playbook -i k8s.ini metrics-server-install.yaml
```

The values file makes Metrics Server select node `InternalIP` addresses and
verify kubelet certificates with the kubeadm cluster CA. The chart generates a
serving certificate so the kube-apiserver also verifies Metrics Server rather
than using `APIService.insecureSkipTLSVerify`.

## Validate

```bash
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl top nodes
kubectl top pods --all-namespaces
kubectl -n kube-system logs deployment/metrics-server
```

The APIService must report `Available=True`, every node must return CPU and
memory values, and the logs must contain no certificate validation failures.

Use Hubble to confirm that the observed traffic matches the policy:

- Metrics Server to node kubelets on TCP `10250`.
- Metrics Server to the kube-apiserver on TCP `6443`.
- The kube-apiserver to Metrics Server on pod TCP `10250`. Cilium observes
  cross-node APIService traffic as the `remote-node` entity in this cluster.
- No DNS requests or unexplained dropped flows.

Kubelet serving certificates rotate before expiration, but Kubernetes still
requires approval of renewed serving CSRs. Keep this manual for the learning
lab, or later deploy a pinned approver that validates node identity and subject
alternative names.

## Upstream sources

- [Metrics Server chart 3.14.0](https://github.com/kubernetes-sigs/metrics-server/releases/tag/metrics-server-helm-chart-3.14.0)
- [Kubelet TLS bootstrap](https://kubernetes.io/docs/reference/access-authn-authz/kubelet-tls-bootstrapping/)
