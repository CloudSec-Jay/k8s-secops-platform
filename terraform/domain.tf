resource "libvirt_domain" "node" {
  for_each = local.nodes

  name        = each.key
  type        = "kvm"
  memory      = each.value.memory_mib
  memory_unit = "MiB"
  vcpu        = each.value.vcpus

  cpu = {
    mode = "host-passthrough"
  }

  os = {
    type = "hvm"
  }

  running   = true
  autostart = true

  devices = {
    disks = [
      {
        device = "disk"

        driver = {
          name  = "qemu"
          type  = "qcow2"
          cache = "none"
          io    = "native"
        }

        source = {
          file = {
            file = libvirt_volume.os_disk[each.key].path
          }
        }

        target = {
          dev = "vda"
          bus = "virtio"
        }
      },
      {
        device    = "cdrom"
        read_only = true

        driver = {
          name = "qemu"
          type = "raw"
        }

        source = {
          file = {
            file = libvirt_volume.cloudinit[each.key].path
          }
        }

        target = {
          dev = "sda"
          bus = "sata"
        }
      }
    ]

    interfaces = [
      {
        model = {
          type = "virtio"
        }

        mac = {
          address = each.value.mac
        }

        source = {
          network = {
            network = libvirt_network.k8s_lab.name
          }
        }

        wait_for_ip = {
          source  = "lease"
          timeout = 300
        }
      }
    ]

    channels = [
      {
        source = {
          unix = {
            mode = "bind"
          }
        }

        target = {
          virt_io = {
            name = "org.qemu.guest_agent.0"
          }
        }
      }
    ]

    consoles = [
      {
        target = {
          type = "serial"
          port = 0
        }
      }
    ]
  }
}
