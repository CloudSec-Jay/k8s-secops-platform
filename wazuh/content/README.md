# Wazuh Detection Content

Reusable Wazuh endpoint and manager content migrated from the Cloud Operations monitoring project.

| Directory | Purpose | Status |
|---|---|---|
| `agent-configs/` | Linux endpoint configuration examples | Replace the manager DNS name and review OS paths |
| `manager-configs/` | Manager and shared group fragments | Contains environment placeholders |
| `rules/` | Linux file-integrity rules `100002` through `100007` | Requires Wazuh rule tests |
| `sca/` | Fedora CIS-oriented assessment policy | Verify benchmark and distribution applicability |
| `tuning/` | File-integrity overrides and suppression decisions | Revalidate against current events |
| `integrations/` | Optional AWS and VirusTotal examples | Credentials must come from an external secret source |
| `active-response/` | Privileged response prototypes | Disabled; security review required |
| `runbooks/` | Alert-specific response guidance | Partial coverage |
| `dashboards/` | Dashboard design notes | No exported dashboard object |
| `evidence/` | Historical, redacted observations | Prior container environments, not proof of this cluster |

The former Minikube, Docker listener, and Podman Quadlet paths were intentionally not migrated.

## Validation

CI checks that every XML file under `wazuh/` and `platform/` is well-formed (see `.github/workflows/validate.yml`).

Generic XML parsing is only a syntax check. Wazuh configuration can contain fragments whose runtime validity depends on Wazuh decoders, parent rules, and field names. Use Wazuh's rule test and configuration tools before deployment.

## Active-response warning

The examples under `active-response/` modify or remove files and were developed as prototypes. Do not mount or enable them in the Kubernetes deployment until they have:

- strict path boundaries and quarantine behavior;
- authentication and authorization for any external approval system;
- unit and integration tests for malformed events and failure modes;
- an operator-approved rollback and evidence-preservation procedure.

Detection should be deployed independently from automatic remediation.
