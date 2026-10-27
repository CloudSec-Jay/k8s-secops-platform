# Remote libvirt Terraform

> **Archived.** The lab no longer runs on libvirt VMs. The control plane is a Hyper-V VM ([`scripts/HyperV/`](../../scripts/HyperV/New-K8sControlPlaneVM.ps1)) and the workers are bare-metal laptops, so this code is kept for reference only. Paths below are as they were before the move: the inventory is now written by hand from [`scripts/Ansible/k8s.ini.example`](../../scripts/Ansible/k8s.ini.example), and the former libvirt host is now `worker-2`.

Terraform runs on the workstation containing this repository and reaches the
libvirt host at `10.0.0.39` through the provider's native SSH transport. The
Terraform source and state remain on the workstation.

It creates four Rocky Linux 10 VMs (`control-plane-1`, `worker-1`, `worker-2`,
`worker-3`)
from a checksum-pinned cloud image, configures them with cloud-init, and
generates the Ansible inventory at `scripts/Ansible/k8s.ini`.

## Connection gate

The provider cannot answer password prompts, so the workstation needs
key-based SSH to the libvirt host. Replace `REMOTE_USER` with an account on
the libvirt host:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/libvirt_host
ssh-copy-id -i ~/.ssh/libvirt_host.pub REMOTE_USER@10.0.0.39
```

Add a matching entry to `~/.ssh/config`:

```
Host 10.0.0.39
    User REMOTE_USER
    IdentityFile ~/.ssh/libvirt_host
    IdentitiesOnly yes
```

This command must succeed with no prompts:

```bash
ssh -o BatchMode=yes REMOTE_USER@10.0.0.39 'virsh -c qemu:///system list --all'
```

Do not disable SSH host-key verification. The account must not need
interactive `sudo`; membership in the libvirt administration group grants
control of virtual machines and should be limited to an appropriate account.

On WSL, the Linux `~/.ssh` is separate from the Windows one. Run these steps
in the same shell that runs Terraform.

## Prerequisites on the workstation

- The Rocky Linux 10 GenericCloud-Base image at
  `~/Downloads/rocky-10/Rocky-10-GenericCloud-Base-10.2-20260525.0.x86_64.qcow2`
  matching the SHA-256 pinned in `variables.tf`.
- A separate Ed25519 key for the VMs at `~/.ssh/k8s_secops_lab`. Its public
  half is installed in each VM by cloud-init.

## Initialize and apply

Create the local, ignored variable file and replace the example values:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output node_ips
```

Commit the generated `.terraform.lock.hcl`. Do not commit Terraform state,
`tfplan`, the generated inventory, private SSH keys, passwords, or other
credentials.

## Reaching the VMs

The VMs use libvirt's NAT `default` network, which is reachable only from the
libvirt host, so SSH and Ansible jump through it:

```bash
ssh -J REMOTE_USER@10.0.0.39 -i ~/.ssh/k8s_secops_lab VM_USER@VM_IP
ansible all -i ../scripts/Ansible/k8s.ini -m ping
```

Run `terraform apply` after any VM is recreated so the inventory picks up new
DHCP addresses.

## Known provider issues (dmacvicar/libvirt 0.9.9)

- **Disks reference file paths, not pool volumes.** With volume-type disks,
  QEMU was denied access to the backing base image on the former Ubuntu
  host (AppArmor). Using `source.file` avoids this; on the Rocky host the pool
  must stay under an SELinux `virt_image_t` path such as
  `/var/lib/libvirt/images`.
- **Volume changes need `-replace`.** The provider can plan an in-place
  volume update and then reject it with "Update Not Supported". Force the
  replacement instead, for example
  `terraform plan -out=tfplan -replace='libvirt_volume.base_image'`.
- **Console `pty` needs a path.** The serial console omits `source`, and
  libvirt allocates a pty automatically.
