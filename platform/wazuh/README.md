# Wazuh on the VM Cluster

The platform deploys Wazuh from the official `wazuh/wazuh-kubernetes` repository. This repository keeps the lab-specific runbook and detection content while leaving upstream manifests at a visible, pinned vendor boundary.

## 1. Stage the reviewed upstream release

```bash
scripts/stage-wazuh-platform.sh
```

The script clones the `WAZUH_VERSION` tag from [`versions.env`](../../versions.env) into the ignored `.cache/` directory. Review upstream release notes and diff the staged tree before changing the pin.

## 2. Satisfy storage first

List the cluster's default storage class and CSI provisioner:

```bash
kubectl get storageclass
kubectl get csidriver
```

The official local overlay contains storage assumptions that must be reconciled with this kubeadm VM cluster. In the staged tree, inspect:

- `envs/local-env/storage-class.yaml`
- `envs/local-env/indexer-resources.yaml`
- `envs/local-env/wazuh-resources.yaml`

Match the StorageClass provisioner to the installed CSI driver. Size claims for index retention and manager queues; the small local defaults are development values, not durability targets.

## 3. Generate or supply TLS certificates

From the staged upstream tree, follow the certificate procedure for the pinned release. Keep generated private keys and certificates under the ignored `.cache/` tree or in a secrets manager; never copy them into this repository.

```bash
cd .cache/wazuh-kubernetes-v4.14.8
bash wazuh/certs/indexer_cluster/generate_certs.sh
```

Self-signed certificates are acceptable for an isolated lab only when their CA is distributed and trusted deliberately. Use certificates from the lab PKI for longer-lived deployments.

## 4. Remove default credentials before exposure

Upstream example credentials are not deployment secrets. Before exposing the dashboard or agent enrollment ports:

1. Replace indexer, dashboard, API, and enrollment defaults using the pinned release's credential procedure.
2. Store secret manifests outside Git and restrict filesystem permissions.
3. Confirm generated values do not appear in shell history, CI logs, or Kubernetes event output.
4. Rotate any credential that was exposed during initial testing.

## 5. Deploy the local overlay

After reviewing storage, resource requests, exposure services, and secrets:

```bash
kubectl apply -k .cache/wazuh-kubernetes-v4.14.8/envs/local-env/
kubectl -n wazuh wait --for=condition=Ready pod --all --timeout=600s
```

Do not apply the repository's default-deny example to the Wazuh namespace until explicit manager, indexer, dashboard, DNS, certificate-generation, and required egress flows have been captured and allowed.

## 6. Expose services deliberately

Cloud `LoadBalancer` services do not automatically receive external addresses on a bare-metal or VM-only cluster. Select and document one lab-appropriate mechanism:

- a private load-balancer implementation for the VM network;
- an ingress or gateway with TLS and restricted source networks; or
- temporary administrator-only `kubectl port-forward` access.

Agent traffic typically needs separate enrollment and event endpoints. Bind them to private lab addresses and restrict source CIDRs. Do not expose the indexer directly.

## 7. Load custom content

Review [`../../wazuh/content/README.md`](../../wazuh/content/README.md) before placing any file in a manager or agent. Test rules with Wazuh tooling and representative benign/malicious samples; validate active-response safety separately.

## 8. Prove the deployment

Capture redacted output for:

```bash
kubectl get nodes -o wide
kubectl get pods,statefulsets,deployments,services,pvc -n wazuh
kubectl get events -n wazuh --sort-by=.lastTimestamp
cilium status
```

Then enroll one disposable endpoint, generate a harmless file-integrity event, verify alert creation, restart a manager pod, and verify data remains available. A green Pod phase alone does not prove ingestion, persistence, or recovery.

## Sources

- [Wazuh deployment on Kubernetes](https://documentation.wazuh.com/current/deployment-options/deploying-with-kubernetes/kubernetes-deployment.html)
- [Wazuh Kubernetes repository](https://github.com/wazuh/wazuh-kubernetes)
