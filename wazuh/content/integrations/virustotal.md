# VirusTotal FIM Integration

**Source:** https://documentation.wazuh.com/current/user-manual/capabilities/malware-detection/virus-total-integration.html

## What This Does

1. FIM detects file changes/additions in monitored directories (rules 100200, 100201)
2. Wazuh submits the file SHA256 to VirusTotal via built-in integration
3. Built-in rule 87105 fires when VT flags the file as malicious
4. Active response triggers `remove-threat.sh` on the agent to delete the file
5. Rules 100092/100093 alert on AR success/failure

## Threat Mapping

| Framework | ID | Technique |
|---|---|---|
| MITRE ATT&CK | T1204.002 | User Execution: Malicious File |
| MITRE ATT&CK | T1565.001 | Data Manipulation: Stored Data Manipulation |
| OWASP | A08:2021 | Software and Data Integrity Failures |
| STRIDE | Tampering | File modification/addition |

## Built-in Wazuh VT Rules (reference)

| Rule | Description |
|---|---|
| 87105 | VirusTotal: Alert — X engine(s) detected this file |
| 87106 | VirusTotal: Alert — No positives found |

## API Key

Replace `API_KEY` in `virustotal.xml` with your VirusTotal API key. Do not commit the key — substitute at deploy time via Ansible or secrets manager.

## Rate Limits

Free VirusTotal API: 4 requests/min. Limit `rule_id` scope to avoid exceeding this. Add more rules only with a premium key.

## Test Cases

**Positive:**
1. Add to agent config:
   ```xml
   <syscheck>
     <directories check_all="yes" realtime="yes">/tmp/malware</directories>
   </syscheck>
   ```
2. `mkdir /tmp/malware` on the monitored agent
3. Drop a known-malicious sample into `/tmp/malware/`
4. Expected chain: FIM detects file → 100201 fires → VT hash submitted → 87105 fires → `remove-threat.sh` runs → 100092 fires

**Negative:**
- Drop a clean file → VT returns 0 positives → 87106 fires, AR does not trigger

## Gaps

- Novel/custom malware with 0 VT hits will not trigger AR (87105 won't fire)
- Free API rate limit: high FIM volume environments will miss submissions
- Fileless execution: no file hash to submit, not covered
- `remove-threat.sh` deletes the file — no quarantine/preservation for forensics
