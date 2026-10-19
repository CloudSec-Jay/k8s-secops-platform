locals {
  node_ips = { for name, node in local.nodes : name => node.ip }
}

resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../scripts/Ansible/k8s.ini"
  file_permission = "0644"

  content = templatefile("${path.module}/templates/k8s.ini.tftpl", {
    nodes            = local.nodes
    node_ips         = local.node_ips
    vm_user          = var.vm_user
    ssh_private_key  = trimsuffix(var.ssh_public_key_path, ".pub")
    libvirt_jumphost = "${var.libvirt_user}@${var.libvirt_host}"
  })
}
