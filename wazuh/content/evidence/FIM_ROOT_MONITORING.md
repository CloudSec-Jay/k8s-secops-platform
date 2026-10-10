# Evidence: File Integrity Monitoring — Whodata Engine (Fedora)

**Target Role:** Detection Engineer / SOC Analyst
**Environment:** Fedora (kernel 6.18), Wazuh Agent 4.9.2, Manager containerized (Podman Quadlet)
**Objective:** Detect permission staging, persistence mechanisms, and privilege escalation via FIM whodata telemetry.

---

## 1. Security Rationale

Standard FIM (realtime/inotify) only records *what* changed. Whodata (auditd integration) adds *who* changed it — the user, effective UID, and process. This is the difference between a noisy checksum alert and an actionable detection.

| Mode | What Changed | Who Changed It | Process |
|------|-------------|----------------|---------|
| realtime (inotify) | ✓ | ✗ | ✗ |
| whodata (auditd) | ✓ | ✓ | ✓ |

MITRE techniques covered by `linux-fim-rules.xml`:

| Rule | Technique | Sub-technique |
|------|-----------|---------------|
| 100002 | File and Directory Permissions Modification | T1222.002 |
| 100003 | Command and Scripting Interpreter: Unix Shell | T1059.004 |
| 100004 | Abuse Elevation Control Mechanism: Sudo | T1548.003 |
| 100005 | Account Manipulation: SSH Authorized Keys | T1098.004 |
| 100006 | Modify Authentication Process: PAM | T1556.003 |
| 100007 | Command and Scripting Interpreter: Python | T1059.006 |

---

## 2. Configuration

### Agent (`/var/ossec/etc/ossec.conf` on Fedora host)

```xml
<syscheck>
  <disabled>no</disabled>
  <frequency>43200</frequency>
  <scan_on_start>yes</scan_on_start>

  <!-- whodata="yes" — triggers auditd kernel-level syscall capture -->
  <directories check_all="yes" realtime="yes" whodata="yes">/etc,/root</directories>
  <directories check_all="yes">/usr/bin,/usr/sbin,/bin,/sbin</directories>
  <directories check_all="yes" realtime="yes" whodata="yes">/etc/audit,/etc/ssh,/etc/pam.d,/etc/sudoers.d</directories>
  <directories check_all="yes" realtime="yes">/tmp,/var/tmp,/dev/shm</directories>
</syscheck>
```

### Whodata Engine Activation

```
audispd-plugins installed — provides builtin_af_unix socket at /var/ossec/queue/sockets/audit
sudo service auditd restart   (systemctl restart blocked on Fedora/RHEL)

wazuh-syscheckd: INFO (6019): File integrity monitoring real-time Whodata engine started.
```

Audit socket confirmed listening:
```
ss -xlp | grep audit
u_str LISTEN  /var/ossec/queue/sockets/audit
```

---

## 3. End-to-End Test: Rule 100002 (T1222.002)

### Attack Simulation

```bash
# Stage a shell script in a monitored path
sudo cp /dev/null /etc/cron.daily/malicious.sh

# Wait for FIM baseline scan (~60s), then add execute permission
sudo chmod +x /etc/cron.daily/malicious.sh
```

### Alert Fired — Wazuh Manager

```json
{
  "rule": {
    "id": "100002",
    "level": 8,
    "description": "Execute permission added to shell script — Inspect file origin and owning process immediately. CIS 3.3. ZT: Assume Breach.",
    "groups": ["fim_permission", "pci_dss_11.5"],
    "mitre": {
      "technique": ["File and Directory Permissions Modification"],
      "tactic": ["Defense Evasion"],
      "id": ["T1222.002"]
    }
  },
  "syscheck": {
    "path": "/etc/cron.daily/malicious.sh",
    "event": "modified",
    "mode": "whodata",
    "changed_fields": ["permission"],
    "perm_after": "rwxr-xr-x",
    "audit": {
      "process": {
        "name": "/usr/bin/chmod",
        "id": "12345"
      },
      "login_user": {
        "name": "jayadmin",
        "id": "1000"
      },
      "effective_user": {
        "name": "root",
        "id": "0"
      }
    }
  }
}
```

**Key fields proving whodata is active:**
- `mode: whodata` — confirms auditd path, not inotify
- `audit.process.name: /usr/bin/chmod` — exact binary that made the change
- `audit.login_user.name: jayadmin` — the logged-in user who invoked sudo
- `audit.effective_user.name: root` — the effective UID at time of syscall

Without whodata, the alert would show `mode: realtime` with no `audit.*` fields — no attribution, no process name.

---

## 4. Detection Chain

```
chmod +x /etc/cron.daily/malicious.sh
        │
        ▼ auditd syscall event (SYSCALL + PATH records)
        │
        ▼ builtin_af_unix → /var/ossec/queue/sockets/audit
        │
        ▼ wazuh-syscheckd receives event, populates changed_fields + perm
        │
        ▼ parent rule 550 fires (syscheck: integrity checksum changed)
        │
        ▼ rule 100002 matches: file=*.sh, changed_fields=permission, perm=*wx
        │
        ▼ alert: level 8, T1222.002, whodata fields populated
```

---

## 5. Rule Source

`wazuh/content/rules/linux_fim_rules.xml`

```xml
<rule id="100002" level="8">
  <if_sid>550</if_sid>
  <field name="file">.sh$</field>
  <field name="changed_fields">^permission$</field>
  <field name="perm" type="pcre2">\w\wx</field>
  <description>Execute permission added to shell script — Inspect file origin and owning process immediately. CIS 3.3. ZT: Assume Breach.</description>
  <mitre>
    <id>T1222.002</id>
  </mitre>
  <group>fim_permission,pci_dss_11.5,</group>
</rule>
```

`\w\wx` matches any permission string ending in execute (`rwxr-xr-x`, `rwx------`, etc.).
`changed_fields=^permission$` ensures rule only fires on permission changes, not content changes.

---

## 6. Gaps (Documented)

- Does not detect chmod on non-.sh/.py executables (ELF binaries, Perl/Ruby scripts)
- Does not detect scripts dropped pre-set +x inside tar/zip extraction
- Does not correlate permission change with subsequent execution (T1059.004)
- Audit rules for `wazuh_fim` key persistence across reboots not yet verified (`auditctl -l | grep wazuh_fim`)
