# Dedicated NAT network for the lab. Nodes get static addresses from
# cloud-init (cloud-init/network-config.yml), so this resource does not depend
# on local.nodes and adding or removing a node leaves the network untouched.
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
      address = local.network_gateway
      prefix  = local.network_prefix

      dhcp = {
        # Pool for anything not listed in local.nodes.
        ranges = [
          {
            start = "192.168.100.100"
            end   = "192.168.100.199"
          }
        ]
      }
    }
  ]
}
