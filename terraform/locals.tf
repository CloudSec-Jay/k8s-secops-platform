locals {
  # The k8s-lab bridge address doubles as each node's gateway and DNS server.
  network_gateway = "192.168.100.1"
  network_prefix  = 24

  # role controls the Ansible inventory group: "control_plane" or "worker".
  # ip and mac must be unique and inside the k8s-lab network (network.tf),
  # outside its DHCP pool (.100-.199). 52:54:00 is the KVM/QEMU MAC prefix.
  # cloud-init sets ip statically on the NIC with this mac.
  nodes = {
    control-plane-1 = {
      role       = "control_plane"
      ip         = "192.168.100.10"
      mac        = "52:54:00:64:00:0a"
      memory_mib = 4096
      vcpus      = 2
    }

    worker-1 = {
      role       = "worker"
      ip         = "192.168.100.21"
      mac        = "52:54:00:64:00:15"
      memory_mib = 8192
      vcpus      = 4
    }

    worker-2 = {
      role       = "worker"
      ip         = "192.168.100.22"
      mac        = "52:54:00:64:00:16"
      memory_mib = 8192
      vcpus      = 4
    }

    worker-3 = {
      role       = "worker"
      ip         = "192.168.100.23"
      mac        = "52:54:00:64:00:17"
      memory_mib = 8192
      vcpus      = 4
    }
  }

  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
}
