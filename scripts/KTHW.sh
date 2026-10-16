#!/bin/bash
set -euo pipefail

VM_USER=${VM_USER:-${USER}}
VM_MEMORY_MB=${VM_MEMORY_MB:-4096}
VM_DISK_GB=${VM_DISK_GB:-30}
VM_VCPUS=${VM_VCPUS:-2}
LIBVIRT_NETWORK=${LIBVIRT_NETWORK:-default}
LIBVIRT_BOOT_DIR=/var/lib/libvirt/boot
UBUNTU_RELEASE=24.04.5
UBUNTU_ISO_NAME=ubuntu-${UBUNTU_RELEASE}-live-server-amd64.iso
UBUNTU_ISO_URL=https://releases.ubuntu.com/24.04/${UBUNTU_ISO_NAME}
UBUNTU_ISO_SHA256=97f3d7ffb032c3eb3b23d2c8be9cc76e60c2c1f2c0146ba5ba9fe01cafae0fd8

usage() {
    cat <<'EOF'
Usage:
  ./KTHW.sh
  UBUNTU_ISO=/absolute/path/to/ubuntu-live-server-amd64.iso ./KTHW.sh
  ./KTHW.sh --teardown

Optional settings: VM_USER, VM_MEMORY_MB, VM_DISK_GB, VM_VCPUS,
LIBVIRT_NETWORK, UBUNTU_ISO. If UBUNTU_ISO is omitted, the pinned Ubuntu
Server ISO is downloaded automatically. VM_USER defaults to your local user.
EOF
}

# Teardown for testing: ./KTHW.sh --teardown
# Destroys the VMs and their disks, and removes known_hosts entries and machines.txt.
# Leaves the ISO, the k8s apt repo and your local SSH key alone.
if [ "${1:-}" = "--teardown" ]; then
    if [ -f machines.txt ]; then
        while read IP FQDN HOST SUBNET; do
            # Rebuilt VMs get new host keys, so forget the old ones
            ssh-keygen -R ${IP} || true
            ssh-keygen -R ${HOST} || true
        done < machines.txt
        rm -f machines.txt
    fi

    for vm in control-1 worker-1 worker-2; do
        if sudo virsh dominfo "$vm" > /dev/null 2>&1; then
            sudo virsh destroy "$vm" 2> /dev/null || true   # stop it (fails if already off)
            # Delete only the VM's own disk (vda), never the attached ISO
            sudo virsh undefine "$vm" --storage vda
        fi
    done
    echo "Teardown complete."
    exit 0
fi

# An Ubuntu live-server ISO is still used; cloud-init only supplies the answers
# that would otherwise be entered in the graphical installer.
DOWNLOAD_UBUNTU_ISO=false
if [ -n "${UBUNTU_ISO:-}" ]; then
    [ -f "$UBUNTU_ISO" ] || { echo "Ubuntu ISO not found: $UBUNTU_ISO" >&2; exit 1; }
    case "$UBUNTU_ISO" in
        /*) ;;
        *) echo "UBUNTU_ISO must be an absolute path: $UBUNTU_ISO" >&2; exit 1 ;;
    esac
    UBUNTU_ISO=$(readlink -f "$UBUNTU_ISO")
else
    UBUNTU_ISO="$LIBVIRT_BOOT_DIR/$UBUNTU_ISO_NAME"
    DOWNLOAD_UBUNTU_ISO=true
fi

# Host machine setup
sudo apt-get update
sudo apt-get install -y \
    ca-certificates \
    cloud-image-utils \
    curl \
    libvirt-clients \
    libvirt-daemon-system \
    openssh-client \
    qemu-kvm \
    virtinst

sudo systemctl enable --now libvirtd
if ! sudo virsh net-info "$LIBVIRT_NETWORK" > /dev/null 2>&1; then
    echo "Libvirt network '$LIBVIRT_NETWORK' does not exist." >&2
    exit 1
fi
if ! sudo virsh net-info "$LIBVIRT_NETWORK" | awk '$1 == "Active:" && $2 == "yes" {found=1} END {exit !found}'; then
    sudo virsh net-start "$LIBVIRT_NETWORK"
fi

# The public key is placed into every installed VM. No password or private key
# is written into the generated seed ISOs.
mkdir -p -m 700 "$HOME/.ssh"
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N ""
fi
SSH_PUBLIC_KEY=$(tr -d '\n' < "$HOME/.ssh/id_ed25519.pub")
sudo install -d -m 755 "$LIBVIRT_BOOT_DIR"

if [ "$DOWNLOAD_UBUNTU_ISO" = true ]; then
    if ! printf '%s  %s\n' "$UBUNTU_ISO_SHA256" "$UBUNTU_ISO" |
        sha256sum --check --status 2> /dev/null; then
        echo "== Downloading pinned Ubuntu Server $UBUNTU_RELEASE ISO (about 4 GB)"
        sudo curl --fail --location --progress-bar \
            --output "$UBUNTU_ISO.download" "$UBUNTU_ISO_URL"
        printf '%s  %s\n' "$UBUNTU_ISO_SHA256" "$UBUNTU_ISO.download" |
            sha256sum --check --status || {
                echo "Downloaded Ubuntu ISO failed SHA-256 verification." >&2
                exit 1
            }
        sudo mv "$UBUNTU_ISO.download" "$UBUNTU_ISO"
        sudo chmod 0644 "$UBUNTU_ISO"
    else
        echo "== Using verified cached Ubuntu Server $UBUNTU_RELEASE ISO"
    fi
fi

# A file in the user's home directory may not be readable by the libvirt QEMU
# account. Keep a root-owned copy in libvirt's boot directory.
INSTALL_ISO="$LIBVIRT_BOOT_DIR/$(basename "$UBUNTU_ISO")"
if [ "$UBUNTU_ISO" != "$INSTALL_ISO" ]; then
    if ! sudo test -f "$INSTALL_ISO" || ! sudo cmp -s "$UBUNTU_ISO" "$INSTALL_ISO"; then
        echo "== Staging Ubuntu ISO for libvirt"
        sudo install -m 0644 "$UBUNTU_ISO" "$INSTALL_ISO"
    fi
else
    INSTALL_ISO=$UBUNTU_ISO
fi

SEED_WORK_DIR=$(mktemp -d)
trap 'rm -rf "$SEED_WORK_DIR"' EXIT

create_vm() {
    local vm_name=$1
    local hostname=$2
    local vm_seed_dir="$SEED_WORK_DIR/$vm_name"
    local seed_iso="$LIBVIRT_BOOT_DIR/$vm_name-seed.iso"

    if sudo virsh dominfo "$vm_name" > /dev/null 2>&1; then
        echo "== $vm_name already exists; skipping VM creation"
        return
    fi

    mkdir -p "$vm_seed_dir"
    cat > "$vm_seed_dir/user-data" <<EOF
#cloud-config
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard:
    layout: us
  identity:
    hostname: $hostname
    username: $VM_USER
    password: "*"
  ssh:
    install-server: true
    allow-pw: false
    authorized-keys:
      - $SSH_PUBLIC_KEY
  storage:
    layout:
      name: direct
  packages:
    - qemu-guest-agent
  late-commands:
    - curtin in-target --target=/target -- sh -c 'echo "$VM_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-k8s-lab'
    - curtin in-target --target=/target -- chmod 0440 /etc/sudoers.d/90-k8s-lab
    - curtin in-target --target=/target -- systemctl enable qemu-guest-agent
EOF
    : > "$vm_seed_dir/meta-data"
    sudo cloud-localds "$seed_iso" "$vm_seed_dir/user-data" "$vm_seed_dir/meta-data"

    echo "== $vm_name: starting unattended Ubuntu installation"
    sudo virt-install \
        --connect qemu:///system \
        --name "$vm_name" \
        --memory "$VM_MEMORY_MB" \
        --vcpus "$VM_VCPUS" \
        --osinfo detect=on,require=off \
        --disk "size=$VM_DISK_GB,bus=virtio,format=qcow2" \
        --disk "path=$seed_iso,device=cdrom,readonly=on" \
        --location "$INSTALL_ISO,kernel=casper/vmlinuz,initrd=casper/initrd" \
        --extra-args "autoinstall console=ttyS0,115200n8 serial" \
        --network "network=$LIBVIRT_NETWORK,model=virtio" \
        --graphics none \
        --console pty,target_type=serial \
        --noautoconsole
}

create_vm control-1 server
create_vm worker-1 node-0
create_vm worker-2 node-1

# Look up each VM's IP from libvirt's DHCP leases (libvirt VM name -> IP)
vm_ip() {
    sudo virsh domifaddr "$1" --source lease 2> /dev/null |
        awk '/ipv4/ {split($4, a, "/"); print a[1]; exit}'
}

wait_for_ssh() {
    local vm_name=$1
    local ip=""
    local deadline=$((SECONDS + 1800))

    echo "== $vm_name: waiting for autoinstall and SSH (up to 30 minutes)" >&2
    while (( SECONDS < deadline )); do
        ip=$(vm_ip "$vm_name")
        if [ -n "$ip" ] && ssh \
            -o BatchMode=yes \
            -o ConnectTimeout=5 \
            -o StrictHostKeyChecking=accept-new \
            "$VM_USER@$ip" true 2> /dev/null; then
            printf '%s\n' "$ip"
            return 0
        fi
        sleep 10
    done

    echo "Timed out waiting for $vm_name. Inspect it with: sudo virsh console $vm_name" >&2
    return 1
}

SERVER_IP=$(wait_for_ssh control-1)
NODE_0_IP=$(wait_for_ssh worker-1)
NODE_1_IP=$(wait_for_ssh worker-2)

# Machine database used by the KTHW labs: IPV4_ADDRESS FQDN HOSTNAME POD_SUBNET
cat << EOF > machines.txt
${SERVER_IP} server.kubernetes.local server
${NODE_0_IP} node-0.kubernetes.local node-0 10.200.0.0/24
${NODE_1_IP} node-1.kubernetes.local node-1 10.200.1.0/24
EOF
cat machines.txt

while read IP FQDN HOST SUBNET; do
  ssh -n "$VM_USER@$IP" hostname
done < machines.txt

for h in $(cut -d " " -f 1 machines.txt); do
    ssh -n "$VM_USER@$h" uptime
done
