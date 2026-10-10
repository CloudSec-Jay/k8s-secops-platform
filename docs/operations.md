# Operations and Recovery

## Daily checks

```bash
kubectl get nodes
kubectl get pods -n wazuh
kubectl get pvc -n wazuh
kubectl get events -n wazuh --sort-by=.lastTimestamp
cilium status
```

Review index capacity, Wazuh queue pressure, certificate expiry, failed agent enrollment, dropped network flows, and pending volumes. Alert on symptoms before they become data loss.

## Change sequence

1. Record the current workload images, configuration revisions, PVC state, and cluster health.
2. Review upstream release notes and security advisories.
3. Back up data and prove that the backup is readable.
4. Apply changes to a disposable or restored environment first.
5. Roll one component at a time where the upstream procedure permits it.
6. Verify ingestion, search, dashboards, endpoint connectivity, and Hubble flows.
7. Record the result and the exact rollback boundary.

## Recovery exercises

- Recreate a worker and rejoin it with kubeadm.
- Restore Wazuh index data into an isolated namespace or cluster.
- Rotate dashboard, API, and enrollment credentials.
- Renew TLS certificates before expiry.
- Restore the control-plane state using the documented etcd backup procedure.
- Confirm a default-deny policy blocks unapproved traffic without blocking DNS or required Wazuh flows.

Keep recovery credentials and backup material outside this repository. Redact host addresses, tokens, usernames, and event payloads before committing evidence.
