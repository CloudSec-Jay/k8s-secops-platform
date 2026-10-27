# cert-manager & Private PKI

Automated certificate lifecycle management for internal cluster services and the Cilium Gateway API.

## Architecture

* **Engine:** `cert-manager` v1.21.2 deployed via Helm in namespace `cert-manager`.
* **Zero-Trust Policy:** [`platform/cilium/manifests/cert-manager.yaml`](../cilium/manifests/cert-manager.yaml) grants least-privilege egress to `kube-apiserver` (ports 6443/443), CoreDNS (port 53), and webhook admission review ingress (ports 10250/10260).
* **Root CA (`lab-ca-issuer`):** A 10-year self-signed internal Root CA stored in Secret `lab-root-ca-keypair` that signs all application certificates (`*.lab.internal`).

## Deployment

The deployment is fully automated via Ansible:

```bash
cd scripts/Ansible
ansible-playbook cert-manager-install.yaml -K
```

`-K` prompts for the `kubeadmin` sudo password.

## Validate

```bash
# Verify pods are healthy
kubectl get pods -n cert-manager

# Verify the ClusterIssuers are ready
kubectl get clusterissuer

# Inspect the Root CA Secret
kubectl get secret -n cert-manager lab-root-ca-keypair
```
