# Archive

Material from earlier versions of the lab, kept for reference. None of it is used by the current hybrid cluster (Hyper-V control plane, bare-metal laptop workers).

| Path | What it was | Why it was retired |
|---|---|---|
| [`terraform/`](terraform/README.md) | Provisioned the libvirt VMs and generated the Ansible inventory | The nodes are no longer libvirt VMs |
| [`image-builder/`](image-builder/rocky10-k8s-base.toml) | Image Builder blueprint for the VM cloud image (cloud-init, `qemu-guest-agent`) | The nodes are installed from the Rocky Linux ISO |
| [`ansible/kvm-host-lan.yaml`](ansible/kvm-host-lan.yaml) and `ansible/templates/` | Forwarded LAN ports on the Wi-Fi KVM host into the NATed VM network | The nodes now have their own LAN addresses |
| [`ansible/storage-setup.yaml`](ansible/storage-setup.yaml) and [`platform/cilium/`](platform/cilium/) | local-path storage and its Cilium policy | Replaced by Longhorn |
| [`scripts/check-host.sh`](scripts/check-host.sh) | Checked that a Linux host could run KVM VMs | The VM host is now Hyper-V on Windows |

Local-only files here, such as `ansible/kvm-host.ini` and Terraform state or plans, stay ignored by Git.
