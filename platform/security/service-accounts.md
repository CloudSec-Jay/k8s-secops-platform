# Kubernetes Service Accounts

Apply least privilege to Kubernetes RBAC and workload identity. Give each workload a dedicated service account instead of using the namespace's `default` account.

## Service account pattern

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: application
  namespace: application
automountServiceAccountToken: false
```

Enable token mounting only when the workload must call the Kubernetes API.

## Namespace-scoped RBAC

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: application-config-reader
  namespace: application
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    resourceNames: ["application-config"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: application-config-reader
  namespace: application
subjects:
  - kind: ServiceAccount
    name: application
    namespace: application
roleRef:
  kind: Role
  name: application-config-reader
  apiGroup: rbac.authorization.k8s.io
```

Use a `ClusterRole` only when access genuinely crosses namespace boundaries.

## Workload identity

Cilium and SPIFFE-compatible components can identify a workload by namespace and service account instead of its changing IP address:

```text
spiffe://cluster.local/ns/application/sa/application
```

## Checklist

- [ ] Every workload has a dedicated service account.
- [ ] `automountServiceAccountToken` is disabled unless required.
- [ ] RBAC is namespace-scoped whenever possible.
- [ ] Rules avoid wildcard verbs and resources.
- [ ] External identity trust is restricted to the exact namespace and service account when configured.
- [ ] Existing Kubernetes objects are adopted deliberately before another tool manages them.
