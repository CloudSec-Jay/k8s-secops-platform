resource "libvirt_cloudinit_disk" "seed" {
  for_each = local.nodes

  name = "${each.key}-cloud-init"

  meta_data = templatefile(
    "${path.module}/cloud-init/meta-data.yml",
    {
      hostname = each.key
    }
  )

  user_data = templatefile(
    "${path.module}/cloud-init/user-data.yml",
    {
      hostname       = each.key
      vm_user        = var.vm_user
      ssh_public_key = local.ssh_public_key
    }
  )

  network_config = templatefile(
    "${path.module}/cloud-init/network-config.yml",
    {
      mac     = each.value.mac
      ip      = each.value.ip
      prefix  = local.network_prefix
      gateway = local.network_gateway
    }
  )
}

resource "libvirt_volume" "cloudinit" {
  for_each = local.nodes

  name = "${each.key}-cloud-init.iso"
  pool = var.storage_pool

  create = {
    content = {
      url = libvirt_cloudinit_disk.seed[each.key].path
    }
  }

  target = {
    format = {
      type = "iso"
    }
  }

  lifecycle {
    replace_triggered_by = [
      libvirt_cloudinit_disk.seed[each.key]
    ]
  }
}
