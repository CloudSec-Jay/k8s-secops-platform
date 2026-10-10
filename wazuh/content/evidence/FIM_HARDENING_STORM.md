# Evidence: FIM Alert Storm — CIS Hardening Run

**Date:** 2026-03-31
**Environment:** Fedora 43, Wazuh Agent 4.14.4, Manager 4.14.4 (Docker single-node)
**Trigger:** `ansible-lockdown.RHEL9-CIS` playbook — CIS Level 1 + 2 hardening applied to local workstation
**Peak alert volume:** ~170,000 FIM events in a single session

---

## 1. What Happened

Running a CIS hardening playbook against a live host that already has Wazuh FIM active with `realtime="yes"` and `whodata="yes"` on `/etc`, `/root`, `/tmp`, `/dev/shm`, and security config paths is a controlled collision between two correct behaviors:

- Ansible touches hundreds of files across monitored directories simultaneously
- Wazuh FIM monitors every file event in real time and generates an alert for each one

Neither system was misconfigured. The storm was the expected result of applying large-scale hardening to a monitored host without pre-staging any suppression.

**inotify queue overflow warning appeared during the run:**

```
wazuh-syscheckd: WARNING (6926): Inotify event queue overflowed.
Events may have been lost. Check '/proc/sys/fs/inotify/max_queued_events'.
```

This confirmed the event rate exceeded the kernel's inotify queue depth — FIM events were being dropped at the source before Wazuh could even process them.

---

## 2. Alert Volume Breakdown

Primary flood sources identified from dashboard:

| Path | Rule | Volume | Cause |
|---|---|---|---|
| `/etc/systemd/system.control/` | 550 (level 7) | Very high | `systemctl set-property` called per unit per property during hardening |
| `/etc/pam.d/` | 550 (level 7) | High | authselect profile creation — every PAM file rewritten |
| `/etc/audit/rules.d/` | 550 (level 7) | High | CIS auditd rules deployed as batch |
| `/etc/ssh/sshd_config.d/` | 550 (level 7) | Medium | SSH drop-in hardening settings |
| `/etc/sudoers.d/` | 100004 (level 12) | Medium | Sudo hardening rules written |
| `/tmp/`, `/dev/shm/` | 554/553 | Medium | lttng-ust, Firefox locks, IDE artifacts |

The `/etc/pam.d/` and `/etc/audit/rules.d/` floods were legitimate hardening activity — correct alerts, wrong time. The `/etc/systemd/system.control/` flood was pure noise: `systemd` writes runtime property overrides to this path as a side effect of `systemctl set-property` calls made by the playbook, and this directory is not a persistence target for attackers.

---

## 3. Triage Approach

**Step 1 — Distinguish signal from noise.**

Not all 170k alerts were noise. Alerts on `/etc/sudoers.d/`, `/etc/pam.d/`, and `/etc/ssh/` were expected and legitimate — the hardening run made real changes to security-critical files. Suppressing them would have hidden evidence of what the playbook actually did.

The question for each noisy path: *is this a path an attacker would use, or is this OS/application churn that only fires during a hardening event?*

**Step 2 — Categorize each flood source.**

| Path | Signal? | Decision |
|---|---|---|
| `/etc/systemd/system.control/` | No — transient runtime dir, not an attacker persistence path | Suppress |
| `/dev/shm/lttng-ust-*` | No — tracing subsystem lifecycle, tmpfs | Suppress |
| `/tmp/org.mozilla.firefox/` | No — browser PID lock files | Suppress |
| `/etc/pam.d/` | Yes — hardening changed auth stack | Keep, document change window |
| `/etc/sudoers.d/` | Yes — sudo policy modified | Keep |
| `/etc/ssh/sshd_config.d/` | Yes — SSH hardened | Keep |

**Step 3 — Choose suppression mechanism.**

Two options available in Wazuh:

- **`<ignore>` in ossec.conf** — agent-side, events never sent to manager. Zero processing cost. No audit trail.
- **Rule-level override** in a tuning XML — manager-side, events arrive but are re-leveled to 2–3 (info/debug). Audit trail preserved at low level.

Decision: use agent-side ignore for paths with zero TP value. Add a rule-level backstop in `linux_fim_tuning.xml` for paths where a faint audit trail has value. Document both in `tuning/suppression-log.md`.

---

## 4. Suppression Decisions Made

All documented in `wazuh/content/tuning/suppression-log.md`.

### `/etc/systemd/system.control/`
- **Mechanism:** `<ignore>` in ossec.conf + rule 100008 (level 3) in `linux_fim_tuning.xml`
- **Rationale:** Attackers targeting systemd persistence write unit files to `/etc/systemd/system/` — that path remains monitored. `system.control/` holds transient runtime property overrides written by `systemctl set-property`, cleared on reboot.
- **Risk accepted:** Agent-side ignore stops events at source. Rule 100008 acts as backstop. `/etc/systemd/system/` coverage unaffected.

### `/dev/shm/lttng-ust-*`
- **Mechanism:** `<ignore type="sregex">` + rule 100009 (level 2)
- **Rationale:** lttng-ust rendezvous objects in tmpfs. Process-lifetime, cleared on reboot. Not a writable persistence path.
- **Risk accepted:** Rule 100003 still fires on `.sh` files anywhere in `/dev/shm`.

### `/tmp/org.mozilla.firefox/`
- **Mechanism:** `<ignore>` + rule 100010 (level 2)
- **Rationale:** Firefox session lock files. Browser PID management, not staging activity.
- **Risk accepted:** Rule 100003 coverage of `/tmp` script drops unaffected.

---

## 5. Structural Fix — Config Deduplication

The alert storm also exposed a config duplication problem. Three Fedora config files existed with overlapping `<syscheck>`, `<localfile>`, and `<sca>` blocks:

- `agent-configs/ossec.conf` — local agent config
- `agent-configs/fedora_config.xml` — stale copy of the group config
- `manager-configs/shared/fedora/agent.conf` — centralized group config pushed from manager

`/var/log/secure` was being collected three times. Syscheck directories were monitored twice (once from each config), which doubled FIM event volume on every monitored path.

**Resolution:**
- `ossec.conf` made authoritative — single source of truth for all agent config
- `<whodata>` provider block consolidated into `ossec.conf`
- All localfiles consolidated (no duplicates)
- `fedora_config.xml` deleted
- `manager-configs/shared/fedora/agent.conf` reduced to a documented stub

Eliminating the duplicate monitoring reduced baseline FIM volume by ~50%.

---

## 6. Rootcheck Alert During Investigation

During the post-storm triage, four rootcheck rule 510 alerts fired:

```
Trojaned version of file detected. — /bin/passwd
```

**Investigation:**

```bash
rpm -Vf /bin/passwd
S.5....T.  c /etc/default/useradd
S.5....T.  c /etc/login.defs
```

- `c` flag = config file, not the binary
- `5` flag on config files = expected — ansible-lockdown modified `/etc/login.defs` (password aging policy) and `/etc/default/useradd`
- The `/bin/passwd` binary itself passed checksum — no `5` flag on the binary entry

**Conclusion:** rootcheck false positive. The rootcheck trojan database uses pattern matching against known backdoor signatures in system binaries. The binary is intact. The flagged files are config files modified by the hardening run with `c` (config) classification in RPM — not the binary itself.

**Risk accepted:** Rootcheck's trojan database is designed for pre-systemd Linux. Pattern-match false positives on clean modern binaries are known behavior. RPM verification is the authoritative check.

---

## 7. Lessons

**Pre-stage suppression before running hardening at scale.**
A change window with known noisy paths pre-suppressed would have reduced the storm from 170k events to a manageable baseline of legitimate change alerts. The storm itself is the evidence that the monitoring was working — but working well means not flooding the analyst.

**inotify queue depth matters.**
`/proc/sys/fs/inotify/max_queued_events` defaults to 16384. A large hardening run saturates this in seconds on a host with broad realtime FIM coverage. For production hardening, either increase the queue depth or stage the hardening in batches.

**Every suppression needs a documented reason.**
Six paths were suppressed during this session. Every one is in `suppression-log.md` with rationale, risk accepted, and date. Suppressing an alert without documentation creates a blind spot that survives the engineer who created it.

**Duplicate config amplifies everything.**
The deduplication fix made as much difference as the tuning rules. Alert volume is a product of event volume × monitoring coverage — if coverage is doubled by duplicate config, every noise problem is twice as bad.

---

## 8. Files Modified

| File | Change |
|---|---|
| `agent-configs/ossec.conf` | Added 3 `<ignore>` entries + `<whodata>` block + missing localfiles |
| `tuning/linux_fim_tuning.xml` | Rules 100008, 100009, 100010 added |
| `tuning/suppression-log.md` | All decisions documented |
| `agent-configs/fedora_config.xml` | Deleted — stale duplicate |
| `manager-configs/shared/fedora/agent.conf` | Reduced to documented stub |
