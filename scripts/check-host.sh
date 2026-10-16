#!/usr/bin/env bash

# This script checks whether a Linux computer is ready to host KVM virtual
# machines. It only reads system information; it does not create or delete VMs.

# Print a heading before the virtualization check.
# printf writes formatted text, and \n starts or ends a line.
printf '\n=== Checking virtualization support ===\n'

# grep searches /proc/cpuinfo, which contains processor information.
# -E enables extended regular expressions so | can mean "or".
# -o selects only matching text.
# -c prints the number of lines containing a match.
# vmx is Intel virtualization support; svm is AMD virtualization support.
# A result greater than zero means Linux can see hardware virtualization.
grep -Eoc '(vmx|svm)' /proc/cpuinfo

# free reports used and available memory.
# -h displays human-readable units such as MiB and GiB.
printf '\n=== Checking memory ===\n'
free -h

# df means "disk free" and reports filesystem space.
# -h displays human-readable units such as GiB.
# / limits the report to the filesystem containing the root directory.
printf '\n=== Checking root filesystem space ===\n'
df -h /

# sudo runs virsh with administrator privileges.
# virsh is the command-line interface for libvirt.
# net-list selects the virtual-network listing operation.
# --all includes both active and inactive networks.
printf '\n=== Checking libvirt networks ===\n'
sudo virsh net-list --all

# systemctl manages systemd services.
# status requests the service state and recent log messages.
# libvirtd is the traditional libvirt management daemon.
# --no-pager prints directly to the terminal instead of opening a pager.
printf '\n=== Checking libvirt service ===\n'
sudo systemctl status libvirtd --no-pager

