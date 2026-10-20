# When upgrading the image, update this name together with source_image_path
# and its pinned SHA-256 in variables.tf.
resource "libvirt_volume" "ubuntu_base" {
  name = "ubuntu-24.04-20260926-amd64-base.qcow2"
  pool = var.storage_pool

  target = {
    format = {
      type = "qcow2"
    }

    permissions = {
      mode = "0644"
    }
  }

  create = {
    content = {
      url = pathexpand(var.source_image_path)
    }
  }
}

resource "libvirt_volume" "os_disk" {
  for_each = local.nodes

  name = "${each.key}.qcow2"
  pool = var.storage_pool

  capacity      = 60
  capacity_unit = "GiB"
  allocation    = 0

  backing_store = {
    path = libvirt_volume.ubuntu_base.path

    format = {
      type = "qcow2"
    }
  }

  target = {
    format = {
      type = "qcow2"
    }
  }

  # An overlay only stores changes on top of its base, so it must be
  # rebuilt whenever the base image is replaced.
  lifecycle {
    replace_triggered_by = [
      libvirt_volume.ubuntu_base
    ]
  }
}
