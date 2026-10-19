# Dedicated NAT network for the lab. DHCP reservations pin each node's IP to
# its MAC address, so kubeadm gets stable addresses while the VMs keep the
# default DHCP configuration from the cloud image.
resource "libvirt_network" "k8s_lab" {
  name      = "k8s-lab"
  autostart = true

  bridge = {
    name = "virbr-k8s"
  }

  forward = {
    mode = "nat"
  }

  ips = [
    {
      address = "192.168.100.1"
      prefix  = 24

      dhcp = {
        # Pool for anything not listed in local.nodes.
        ranges = [
          {
            start = "192.168.100.100"
            end   = "192.168.100.199"
          }
        ]

        hosts = [
          for name, node in local.nodes : {
            name = name
            mac  = node.mac
            ip   = node.ip
          }
        ]
      }
    }
  ]
}
