# Suppression Log

Every suppression decision documented with rationale and date.
Suppressing an alert without documentation is a blind spot, not a fix.

---

## Active Suppressions

### `/tmp/python-languageserver-cancellation`
- **Type:** syscheck ignore (ossec.conf)
- **Rule suppressed:** 554 (file added) parent
- **Rationale:** VS Code Python language server writes cancellation token files here constantly. Zero TP value — not a script drop, not executable, created by a known IDE process.
- **Risk accepted:** Confirms we are not blindly suppressing all of `/tmp` — rule 100003 still fires on `.sh` files.
- **Date:** 2026-03-09

### `/tmp/gdk-pixbuf-glycin-tmp`, `/tmp/node-compile-cache`, `/tmp/aws-toolkit-vscode`, `/tmp/hsperfdata_jayadmin`
- **Type:** syscheck ignore (ossec.conf)
- **Rule suppressed:** 554/553 parents
- **Rationale:** Desktop/IDE runtime artifacts. GDK image cache, Node.js compile cache, AWS Toolkit temp files, JVM perf data. All are process-lifetime objects written by known applications.
- **Risk accepted:** Path-specific ignores — `/tmp` script drop detection (rule 100003) unaffected.
- **Date:** 2026-03-09

### `/etc/systemd/system.control`
- **Type:** syscheck ignore (ossec.conf) + rule-level override rule 100008 (linux_fim_tuning.xml)
- **Path:** `/etc/systemd/system.control/`
- **Rationale:** Written by `systemctl set-property` and systemd cgroup accounting at runtime. Attackers targeting systemd persistence write to `/etc/systemd/system/` (unit file drops), not `system.control/` which is a transient override directory cleared on reboot.
- **Risk accepted:** Agent-side ignore stops events at source. Rule 100008 (level 3) acts as backstop if ignore is bypassed. Real systemd persistence path `/etc/systemd/system/` is unaffected — still monitored.
- **Trigger:** Alert flood after ansible-lockdown CIS hardening run (2026-03-31).
- **Date:** 2026-03-31

### `/dev/shm/lttng-ust-*`
- **Type:** syscheck ignore (ossec.conf) + rule-level override rule 100009 (linux_fim_tuning.xml)
- **Path:** `/dev/shm/lttng-ust-` (sregex prefix match)
- **Rationale:** Linux Trace Toolkit next-gen userspace tracing rendezvous objects. Created/destroyed by instrumented applications (Firefox, GNOME). `/dev/shm` is tmpfs — cleared on reboot, not a persistence path.
- **Risk accepted:** Rule 100003 still fires on `.sh` files in `/dev/shm`. Only the `lttng-ust-` prefix is suppressed.
- **Trigger:** Alert flood after ansible-lockdown CIS hardening run (2026-03-31).
- **Date:** 2026-03-31

### `/tmp/org.mozilla.firefox/`
- **Type:** syscheck ignore (ossec.conf) + rule-level override rule 100010 (linux_fim_tuning.xml)
- **Path:** `/tmp/org.mozilla.firefox/`
- **Rationale:** Firefox creates `lock` and `.parentlock` files on start, removes them on clean exit. Well-known browser PID lock pattern, not a staging vector.
- **Risk accepted:** Rule 100003 still fires on `.sh` files in `/tmp`. Only the `org.mozilla.firefox/` prefix is suppressed.
- **Trigger:** Alert flood after ansible-lockdown CIS hardening run (2026-03-31).
- **Date:** 2026-03-31

---

## Suppression Backlog (to evaluate)

- IDE temp files flooding `/tmp` — 657 FIM hits/day noted 2026-03-09. Current path ignores cover most sources. Re-evaluate after next noisy session.
