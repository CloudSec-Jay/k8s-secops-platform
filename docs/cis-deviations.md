# CIS Benchmark Deviations

The Kubernetes nodes are hardened with the [Ansible Lockdown RHEL10-CIS](https://github.com/ansible-lockdown/RHEL10-CIS) role, release `1.1.2` (CIS Red Hat Enterprise Linux 10 Benchmark v1.0.1, Level 1 and Level 2), pinned in [`scripts/Ansible/requirements.yml`](../scripts/Ansible/requirements.yml). [`cis-hardening.yaml`](../scripts/Ansible/cis-hardening.yaml) applies it one node at a time.

Every control runs except the ones below. Each is waived because Kubernetes, Cilium, or this hardware needs it, and the overrides live in [`vars/cis-exceptions.yml`](../scripts/Ansible/vars/cis-exceptions.yml) and [`group_vars/baremetal.yml`](../scripts/Ansible/group_vars/baremetal.yml).

The authselect and PAM controls (5.3.1.x, including account lockout and password history) also did not run: the role applies them only with `rhel10cis_disruption_high: true`, which is off. They need a separate, supervised run.

| Control | Requirement | Why it is waived | Compensating control |
| :--- | :--- | :--- | :--- |
| 1.1.1.6 | `overlay` kernel module not available | containerd's default overlayfs snapshotter needs it; without it no pod starts | Containers are confined by SELinux (`container_t`) |
| 1.1.1.10 | `usb-storage` kernel module not available | worker-2's 1 TB USB SSD is the planned backup target | Physical access to the laptops is limited to the home |
| 1.4.1 | Bootloader password set | **Pending, not waived.** Needs a real `grub2-mkpasswd-pbkdf2` hash stored with ansible-vault; the role default is a placeholder | LUKS still protects the laptops' disks at rest |
| 3.1.2 | Wireless interfaces not available (laptops only) | The role runs `nmcli radio all off`, and Wi-Fi is the laptops' only network link | None needed on the control plane, which has no wireless adapter, so the control still applies there |
| 3.3.1.1–3.3.1.3 | IPv4 forwarding disabled | Kubernetes and Cilium route pod and Service traffic through every node | Cilium network policy with a cluster-wide default deny |
| 3.3.1.12 | `net.ipv4.conf.all.rp_filter = 1` | The Cilium agent sets it to 0 at startup; the kernel uses the stricter of `all` and the per-interface value, so enforcing 1 fights Cilium | 3.3.1.13 (`default.rp_filter = 1`) still applies |
| Section 4 | firewalld enabled with a DROP zone | Would block the kubelet, etcd, Cilium VXLAN and health checks, and NodePorts | Planned: Cilium host firewall ([SG-12](security-gaps.md#sg-12-node-traffic-is-not-filtered)) |
| 6.1.1–6.1.3 | AIDE installed and run | A second file-integrity tool beside Wazuh, whose reports stay on the host it checks | Wazuh agent FIM (`syscheck` with `whodata`) on every node, alerting off-host. **Open until the agents are deployed** |
| 6.3.2.x | Audit logs kept, never deleted; system halted when audit space runs low | The root filesystem is shared with Longhorn replicas and container images, so unbounded logs would fill it and halting a node takes its workloads down | Logs rotate (`rotate`) and low space is logged (`syslog`); audit logs are to be shipped off-host by the Wazuh agent |

## Rollout

1. Run the role's audit or an OpenSCAP scan first to record the baseline. The role's check mode is not guaranteed.
2. Harden one node per run, with its console within reach: `worker-1`, then `control-plane-1` (take a Hyper-V checkpoint first and delete it afterwards), then `worker-2`.
3. After each run, the playbook checks that IPv4 forwarding and bridge netfilter are still on and that the node is `Ready`. Also check Cilium (`cilium-dbg status --brief`), that pods start, and `ausearch -m avc -ts recent`.
4. Once all three nodes have passed, `cis-hardening.yaml` runs as the last step of `site.yaml`, after Cilium, because it checks that each node is `Ready`. All three nodes were hardened and rebooted on 2026-10-27 and passed these checks.

## Before changing the role version

Re-read the new release's `defaults/main/main.yml` and the tasks behind each control above. Rule numbers and defaults change between benchmark versions, and an override that no longer matches a rule silently stops applying.
