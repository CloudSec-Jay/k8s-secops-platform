# Argo CD

GitOps controller for the lab. Argo CD runs in the `argocd` namespace, pulls
this public repository from GitHub over outbound HTTPS, and syncs the
`Application`s in `apps/` into the cluster.

## Ownership boundary

| Layer | Managed by |
| :--- | :--- |
| Control-plane VM, node preparation, kubeadm | Hyper-V script (`scripts/HyperV/`), Ansible |
| Cilium CNI | Ansible (`scripts/Ansible/cilium-install.yaml`); Argo CD cannot repair the network it runs on |
| Argo CD install | Ansible bootstrap (`scripts/Ansible/argocd-install.yaml`) |
| Everything in `apps/` | Argo CD |

## Layout

```text
platform/argocd/
├── values.yaml          Helm values for the argo-cd chart (bootstrap)
├── projects/
│   └── platform.yaml    AppProject: which repo, namespaces and kinds apps may use
└── apps/
    ├── cilium-policies.yaml  platform/cilium/manifests/
    ├── metrics-server.yaml   upstream chart + platform/metrics-server/values.yaml
    ├── cert-manager.yaml     upstream chart + platform/cert-manager/
    └── gateway-api.yaml      platform/gateway-api/
```

## Upstream sources

<!-- TODO: record the pinned chart version and the release URL you reviewed. -->

- Chart: <https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd>
- Application spec: <https://argo-cd.readthedocs.io/en/stable/user-guide/application-specification/>
- Projects: <https://argo-cd.readthedocs.io/en/stable/user-guide/projects/>

## Bootstrap

<!-- TODO: the order of steps, from Cilium to the first synced Application. -->

## Validation

<!-- TODO: commands and redacted evidence showing each app Synced and Healthy. -->
