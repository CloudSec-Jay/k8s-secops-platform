#!/usr/bin/env bash
set -Eeuo pipefail

# Provision three Ubuntu 24.04 KVM virtual machines for a kubeadm lab.
# This script stops at the VM boundary: it does not install containerd,
# Kubernetes, Cilium, Wazuh, or run kubeadm.
#
# Default layout:
#   control-plane-1  2 vCPUs  4096 MiB RAM  30 GiB disk
#   worker-1         4 vCPUs  8192 MiB RAM  30 GiB disk
#   worker-2         4 vCPUs  8192 MiB RAM  30 GiB disk

# -E makes ERR traps inherited by functions and command substitutions.
# -e exits when an unhandled command fails.
# -u rejects references to unset variables.
# -o pipefail makes a pipeline fail when any command in it fails.

readonly IMAGE_NAME="ubuntu-24.04-server-cloudimg-amd64.img"
readonly IMAGE_RELEASE="20260926"
readonly IMAGE_SHA256="6a81c37564db9b1ee84e141922625e1d7c5b389b99bb3c572e0243607d5bb4d2"

# These defaults can be overridden for one invocation, for example:
#   SOURCE_IMAGE=/path/to/image.img LIBVIRT_NETWORK=default ./create-kvm-cluster-vms.sh
readonly SOURCE_IMAGE="${SOURCE_IMAGE:-$HOME/Downloads/$IMAGE_NAME}"
readonly IMAGE_DIRECTORY="${IMAGE_DIRECTORY:-/var/lib/libvirt/images/k8s-secops-lab}"
readonly BASE_IMAGE="$IMAGE_DIRECTORY/ubuntu-24.04-$IMAGE_RELEASE-amd64-base.qcow2"
readonly LIBVIRT_NETWORK="${LIBVIRT_NETWORK:-default}"
readonly SSH_PUBLIC_KEY_FILE="${SSH_PUBLIC_KEY_FILE:-$HOME/.ssh/id_ed25519.pub}"
readonly VM_LOGIN_USER="${VM_LOGIN_USER:-$(id -un)}"
readonly VM_DISK_SIZE="${VM_DISK_SIZE:-30G}"

# Parallel arrays use the same index for a VM's name, memory, and CPU count.
readonly -a VM_NAMES=("control-plane-1" "worker-1" "worker-2")
readonly -a VM_MEMORY_MIB=(4096 8192 8192)
readonly -a VM_VCPUS=(2 4 4)

usage() {
    printf '%s\n' \
        "Usage: $0" \
        "" \
        "Creates three KVM VMs only; it does not install Kubernetes." \
        "" \
        "Optional environment variables:" \
        "  SOURCE_IMAGE         Ubuntu cloud image path" \
        "  IMAGE_DIRECTORY      Destination for VM disks" \
        "  LIBVIRT_NETWORK      Libvirt network name (default: default)" \
        "  SSH_PUBLIC_KEY_FILE  Public key installed in each VM" \
        "  VM_LOGIN_USER        User created in each VM" \
        "  VM_DISK_SIZE         Disk capacity (default: 30G)"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if (( $# != 0 )); then
    usage >&2
    exit 2
fi

# Running the entire script as root would make $HOME and the SSH key point at
# root's account. The script uses sudo only for individual libvirt operations.
if (( EUID == 0 )); then
    printf 'Run this script as your normal user, without sudo.\n' >&2
    exit 1
fi

# Confirm that every required command is installed before creating anything.
for required_command in cloud-localds qemu-img sha256sum sudo virsh virt-install; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        printf 'Missing required command: %s\n' "$required_command" >&2
        exit 1
    fi
done

if [[ ! -f "$SOURCE_IMAGE" ]]; then
    printf 'Ubuntu cloud image not found: %s\n' "$SOURCE_IMAGE" >&2
    exit 1
fi

if [[ ! -f "$SSH_PUBLIC_KEY_FILE" ]]; then
    printf 'SSH public key not found: %s\n' "$SSH_PUBLIC_KEY_FILE" >&2
    exit 1
fi

# Linux user names are deliberately restricted before inserting the value into
# YAML and passing it to cloud-init.
if [[ ! "$VM_LOGIN_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    printf 'Unsupported VM_LOGIN_USER: %s\n' "$VM_LOGIN_USER" >&2
    exit 1
fi

printf 'Verifying source image checksum...\n'
printf '%s  %s\n' "$IMAGE_SHA256" "$SOURCE_IMAGE" | sha256sum --check --status
printf 'Source image checksum is valid.\n'

# Cache sudo credentials now so a prompt does not appear halfway through VM
# creation. -v validates or refreshes the current sudo credential timestamp.
sudo -v

if ! sudo virsh net-info "$LIBVIRT_NETWORK" >/dev/null 2>&1; then
    printf 'Libvirt network does not exist: %s\n' "$LIBVIRT_NETWORK" >&2
    exit 1
fi

if [[ "$(sudo virsh net-info "$LIBVIRT_NETWORK" | awk '/^Active:/ {print $2}')" != "yes" ]]; then
    printf 'Starting libvirt network: %s\n' "$LIBVIRT_NETWORK"
    sudo virsh net-start "$LIBVIRT_NETWORK"
fi

# install -d creates the directory and -m 0755 sets its permissions.
sudo install -d -m 0755 "$IMAGE_DIRECTORY"

if [[ -e "$BASE_IMAGE" ]]; then
    printf 'Verifying existing cached base image...\n'
    printf '%s  %s\n' "$IMAGE_SHA256" "$BASE_IMAGE" |
        sudo sha256sum --check --status
else
    printf 'Copying verified Ubuntu base image...\n'
    # -m 0644 lets libvirt read the immutable backing image.
    sudo install -m 0644 "$SOURCE_IMAGE" "$BASE_IMAGE"
fi

# Read the public key into a variable. The private key is never read or copied.
readonly SSH_PUBLIC_KEY="$(<"$SSH_PUBLIC_KEY_FILE")"

# mktemp -d creates a uniquely named temporary directory. The EXIT trap removes
# only that directory after the script finishes or encounters an error.
CLOUD_INIT_WORK_DIRECTORY="$(mktemp -d)"
readonly CLOUD_INIT_WORK_DIRECTORY
trap 'rm -rf -- "$CLOUD_INIT_WORK_DIRECTORY"' EXIT

create_vm() {
    local vm_name="$1"
    local memory_mib="$2"
    local vcpus="$3"
    local disk_image="$IMAGE_DIRECTORY/$vm_name.qcow2"
    local seed_image="$IMAGE_DIRECTORY/$vm_name-seed.iso"
    local vm_cloud_init_directory="$CLOUD_INIT_WORK_DIRECTORY/$vm_name"

    if sudo virsh dominfo "$vm_name" >/dev/null 2>&1; then
        printf '%s already exists; leaving it unchanged.\n' "$vm_name"
        return 0
    fi

    # Refuse to guess when leftover storage exists without a VM definition.
    # This protects an existing disk from accidental replacement.
    if sudo test -e "$disk_image" || sudo test -e "$seed_image"; then
        printf 'Storage exists for %s, but its VM is not defined.\n' "$vm_name" >&2
        printf 'Inspect these files before retrying: %s %s\n' "$disk_image" "$seed_image" >&2
        return 1
    fi

    mkdir -p "$vm_cloud_init_directory"

    # This heredoc expands $vm_name, $VM_LOGIN_USER, and $SSH_PUBLIC_KEY while
    # producing the cloud-init YAML consumed during the VM's first boot.
    cat >"$vm_cloud_init_directory/user-data" <<EOF
#cloud-config
hostname: $vm_name
manage_etc_hosts: true

users:
  - default
  - name: $VM_LOGIN_USER
    groups: [adm, sudo]
    shell: /bin/bash
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    lock_passwd: true
    ssh_authorized_keys:
      - $SSH_PUBLIC_KEY

ssh_pwauth: false
disable_root: true
package_update: true
packages:
  - qemu-guest-agent

runcmd:
  - [systemctl, enable, --now, qemu-guest-agent]
EOF

    cat >"$vm_cloud_init_directory/meta-data" <<EOF
instance-id: $vm_name
local-hostname: $vm_name
EOF

    printf 'Creating %s disk (%s)...\n' "$vm_name" "$VM_DISK_SIZE"
    # -f declares the new format, -F declares the backing-image format, and
    # -b makes the verified Ubuntu image the read-only backing image.
    sudo qemu-img create \
        -f qcow2 \
        -F qcow2 \
        -b "$BASE_IMAGE" \
        "$disk_image" \
        "$VM_DISK_SIZE"

    # cloud-localds turns user-data and meta-data into a NoCloud seed image.
    sudo cloud-localds \
        "$seed_image" \
        "$vm_cloud_init_directory/user-data" \
        "$vm_cloud_init_directory/meta-data"
    sudo chmod 0644 "$seed_image"

    printf 'Defining and starting %s...\n' "$vm_name"
    # virt-install flag guide:
    # --connect selects the system-wide libvirt instance.
    # --name sets the persistent libvirt domain name.
    # --memory assigns RAM in MiB; --vcpus assigns virtual CPU threads.
    # --cpu host-passthrough exposes the host CPU features to the guest.
    # --import boots the prepared disk instead of running an OS installer.
    # --os-variant supplies Ubuntu-specific virtualization defaults.
    # The first --disk attaches the writable OS disk using the virtio bus.
    # cache=none with io=native avoids double caching and uses native AIO.
    # The second --disk attaches cloud-init data as a read-only CD-ROM.
    # --network connects a virtio network adapter to the libvirt network.
    # --channel adds the communication path used by qemu-guest-agent.
    # --graphics none creates a headless server VM.
    # --console adds a serial console for virsh console troubleshooting.
    # --noautoconsole returns to this script instead of attaching the console.
    sudo virt-install \
        --connect qemu:///system \
        --name "$vm_name" \
        --memory "$memory_mib" \
        --vcpus "$vcpus" \
        --cpu host-passthrough \
        --import \
        --os-variant ubuntu24.04 \
        --disk "path=$disk_image,format=qcow2,bus=virtio,cache=none,io=native" \
        --disk "path=$seed_image,device=cdrom,readonly=on" \
        --network "network=$LIBVIRT_NETWORK,model=virtio" \
        --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0 \
        --graphics none \
        --console pty,target_type=serial \
        --noautoconsole
}

get_vm_ipv4() {
    local vm_name="$1"
    local address_source
    local address

    # Try the guest agent first. During early boot it might not be ready, so
    # fall back to the address recorded in libvirt's DHCP lease database.
    for address_source in agent lease; do
        address="$(
            sudo virsh domifaddr "$vm_name" --source "$address_source" 2>/dev/null |
                awk '$3 == "ipv4" {
                    sub(/\/.*/, "", $4)
                    if ($4 !~ /^127\./) {
                        print $4
                        exit
                    }
                }'
        )" || true

        if [[ -n "$address" ]]; then
            printf '%s\n' "$address"
            return 0
        fi
    done

    return 1
}

wait_for_vm_ipv4() {
    local vm_name="$1"
    local deadline=$((SECONDS + 600))
    local address

    # Poll every five seconds for up to ten minutes. The deadline guarantees
    # that a DHCP or boot failure cannot make the script wait forever.
    while (( SECONDS < deadline )); do
        if address="$(get_vm_ipv4 "$vm_name")"; then
            printf '%s\n' "$address"
            return 0
        fi
        sleep 5
    done

    return 1
}

# ${!VM_NAMES[@]} expands to the array indexes: 0, 1, and 2. Each iteration
# uses one index to select the matching name, memory allocation, and CPU count.
for index in "${!VM_NAMES[@]}"; do
    create_vm \
        "${VM_NAMES[$index]}" \
        "${VM_MEMORY_MIB[$index]}" \
        "${VM_VCPUS[$index]}"
done

printf '\nVM provisioning is complete. Kubernetes was not installed.\n'
sudo virsh list --all

printf '\nWaiting for VM IP addresses (up to ten minutes per VM)...\n'
declare -A VM_IP_ADDRESSES=()
for vm_name in "${VM_NAMES[@]}"; do
    if vm_ip="$(wait_for_vm_ipv4 "$vm_name")"; then
        VM_IP_ADDRESSES["$vm_name"]="$vm_ip"
        printf '  %-16s %s\n' "$vm_name" "$vm_ip"
    else
        printf '  Timed out waiting for %s\n' "$vm_name" >&2
    fi
done

printf '\nWhen cloud-init and SSH are ready, connect with:\n'
for vm_name in "${VM_NAMES[@]}"; do
    if [[ -n "${VM_IP_ADDRESSES[$vm_name]:-}" ]]; then
        printf '  ssh %s@%s\n' "$VM_LOGIN_USER" "${VM_IP_ADDRESSES[$vm_name]}"
    else
        printf '  %s: IP address unavailable\n' "$vm_name"
    fi
done
