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
    disks = concat([
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
      ],
      # Whole host disk for Garage backups, on the one node named in
      # var.backup_disk. The serial gives the guest a stable
      # /dev/disk/by-id/virtio-backup-ssd path whatever the kernel names it.
      [
        for disk in(var.backup_disk == null ? [] : [var.backup_disk]) : {
          device = "disk"
          serial = "backup-ssd"

          driver = {
            name  = "qemu"
            type  = "raw"
            cache = "none"
            io    = "native"
          }

          source = {
            block = {
              dev = disk.device
            }
          }

          target = {
            dev = "vdb"
            bus = "virtio"
          }
        } if disk.node == each.key
    ])

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

        # Static addresses never appear as DHCP leases, so ask the guest
        # agent. The network filter skips 127.0.0.1, which the agent
        # reports before the NIC is configured.
        wait_for_ip = {
          source  = "agent"
          network = "192.168.100.0/24"
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
