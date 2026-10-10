# Wazuh Dashboards

Notes on dashboard configuration. Wazuh uses OpenSearch Dashboards under the hood — visualizations are built with KQL queries on the `wazuh-alerts-*` index.

---

## Dashboards to Build

### 1. Security Events Overview
High-level triage view.

| Panel | Query | Type |
|---|---|---|
| Alerts by severity (last 24h) | `rule.level: [9 TO *]` | Bar chart |
| Top 10 triggered rules | `*` grouped by `rule.id` | Table |
| Alerts by host | `*` grouped by `agent.name` | Table |
| Timeline | `*` over time | Line chart |

### 2. Authentication & Brute Force
```kql
rule.groups: authentication_failed OR rule.groups: authentication_success
```

| Panel | Query |
|---|---|
| Failed logins by source IP | `rule.groups: authentication_failed` grouped by `data.srcip` |
| Brute force → success sequence | `rule.id: 5710 OR rule.id: 5715` |
| Successful logins after failures | correlate events on same srcip |

### 3. File Integrity (FIM)
```kql
rule.groups: syscheck
```

| Panel | Query |
|---|---|
| Modified files by path | grouped by `syscheck.path` |
| FIM events on sensitive paths | `syscheck.path: /etc/passwd OR /etc/shadow OR /etc/sudoers` |

### 4. Privilege Escalation
```kql
rule.mitre.technique: T1548 OR rule.mitre.technique: T1078
```

---

## Useful KQL Patterns

```kql
# High severity events on a specific host
agent.name: "web-01" AND rule.level: [12 TO 15]

# MITRE technique filter
rule.mitre.technique: "T1110"

# Exclude known noise
NOT rule.id: 5501 AND NOT agent.name: "monitoring-host"
```

---

## Export / Import

Dashboards can be exported from OpenSearch Dashboards → Stack Management → Saved Objects → Export.
Store exported `.ndjson` files here for version control.
