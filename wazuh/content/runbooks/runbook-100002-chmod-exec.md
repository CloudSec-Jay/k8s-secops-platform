# Runbook: 100002 — Execute Permission Added to Shell Script

## Trigger
- **Rule ID:** 100002
- **Rule Name:** Execute permission added to shell script
- **Severity:** 8 — High
- **MITRE:** T1222.002 — File and Directory Permissions Modification: Linux/Mac
- **OWASP:** A05:2025 — Security Misconfiguration
- **STRIDE:** Elevation of Privilege

## What This Alert Means
An execute bit was set on a `.sh` file — a common attacker technique to stage a script for execution after dropping it onto the system.

## Severity & SLA
| Severity | Response SLA |
|---|---|
| Critical (15) | 15 min |
| High (12) | 1 hr |
| Medium (9) | 4 hr |

This rule fires at level 8. Escalate to level 12 if file is in `/tmp`, `/var/tmp`, or `/dev/shm` (correlates with rule 100003).

## Triage Steps
1. Identify the file and its origin:
   ```bash
   stat /path/to/file
   file /path/to/file
   sha256sum /path/to/file
   ```
2. Identify who set the permission:
   ```bash
   ausearch -f /path/to/file --start today
   ```
3. Check what process created or modified it:
   ```bash
   ausearch -f /path/to/file -i | grep -E 'pid|uid|comm'
   ```
4. Check if the script has been executed since the permission change:
   ```bash
   ausearch -k exec -i --start today | grep /path/to/file
   ```
5. Compare file hash against allowlist:
   ```bash
# Check the approved executable allowlist when one is configured
   cat /path/to/file | head -5
   ```

## Containment Actions
- Active response (`executable_perm.py`) removes the exec bit automatically — verify it ran:
  ```bash
  ls -la /path/to/file   # should show no +x
  ```
- If active response did not fire or file is in a sensitive path (`/etc`, `/root`, `/usr`):
  ```bash
  chmod -x /path/to/file
  chattr +i /path/to/file   # immutable until reviewed
  ```
- If the script has already executed: isolate the host from the network immediately.

## Eradication Steps
- If unauthorized: remove the file and audit for copies:
  ```bash
  find / -name "filename.sh" 2>/dev/null
  ```
- Review cron jobs for persistence:
  ```bash
  crontab -l -u [user]
  cat /etc/cron.d/*
  ls /etc/cron.daily/ /etc/cron.hourly/
  ```
- Review systemd user units:
  ```bash
  ls ~/.config/systemd/user/
  systemctl list-timers --all
  ```

## Recovery Steps
- Restore file from known-good backup if it was a legitimate script tampered with.
- Re-audit FIM baseline after removal:
  ```bash
  /var/ossec/bin/agent_control -r -a   # force FIM rescan
  ```
- Review recent logins around the time of the alert:
  ```bash
  last -i | head -20
  lastb | head -20
  ```

## Evidence to Collect
- [ ] Wazuh alert JSON: `/var/ossec/logs/alerts/alerts.json` — filter by rule.id 100002
- [ ] `ausearch` output for the file path
- [ ] `sha256sum` of the file
- [ ] Output of `stat` on the file (timestamps, owner, inode)
- [ ] Crontab and systemd unit listings

## Escalation Path
- **File is in the approved allowlist and owner is a CI/CD service account** → false positive, document in `wazuh/content/tuning/suppression-log.md`, close
- **File is in `/tmp`, `/var/tmp`, `/dev/shm`** → high-confidence staging, escalate immediately
- **File has been executed** → treat as active incident, isolate host, page IR lead
- **Unknown origin** → preserve evidence, escalate within SLA

## References
- Rule file: `wazuh/content/rules/linux_fim_rules.xml`
- Active response prototype: `wazuh/content/active-response/executable_perm.py`
- Allowlist: create and document an environment-specific approved executable allowlist
- MITRE: https://attack.mitre.org/techniques/T1222/002/
- NIST: IR-4 (Incident Handling), IR-5 (Incident Monitoring)
