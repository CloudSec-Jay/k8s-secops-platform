variable "libvirt_host" {
  description = "IPv4 address or DNS name of the remote libvirt host."
  type        = string
  default     = "10.0.0.39"
}

variable "libvirt_user" {
  description = "SSH account used to reach the remote libvirt host."
  type        = string
}

variable "storage_pool" {
  description = "Remote libvirt pool that will contain the virtual machine disks."
  type        = string
  default     = "default"
}

# Rocky Linux 10.2 GenericCloud-Base image, build 20260525.0, from
# https://dl.rockylinux.org/pub/rocky/10/images/x86_64/
# SHA-256 taken from that image's .CHECKSUM file.
variable "source_image_path" {
  description = "Pinned Rocky Linux cloud image path"
  type        = string
  default     = "~/Downloads/rocky-10/Rocky-10-GenericCloud-Base-10.2-20260525.0.x86_64.qcow2"

  validation {
    condition = try(
      filesha256(pathexpand(var.source_image_path)) == "9fc9e9ff16888bb68ac39b0392e25c9c92684d50c85f1cce6ab549363bbc4b48",
      false
    )
    error_message = "The Rocky Linux image is missing or its SHA-256 does not match the pinned release."
  }
}

variable "backup_disk" {
  description = "Host disk passed whole to one node for Garage backups, or null for none. Its contents are erased when the node formats it."
  type = object({
    node   = string
    device = string
  })
  default = null

  validation {
    condition     = var.backup_disk == null || startswith(try(var.backup_disk.device, ""), "/dev/disk/by-id/")
    error_message = "backup_disk.device must be a /dev/disk/by-id/ path, which stays the same across reboots and replugs; /dev/sdX can change."
  }
}

variable "vm_user" {
  description = "Linux login account created inside each VM."
  type        = string
}

variable "ssh_public_key_path" {
  description = "Public SSH key installed in each VM."
  type        = string
  default     = "~/.ssh/k8s_secops_lab.pub"

  validation {
    condition = try(
      startswith(
        trimspace(file(pathexpand(var.ssh_public_key_path))),
        "ssh-ed25519 "
      ),
      false
    )
    error_message = "ssh_public_key_path must reference a readable Ed25519 public key."
  }
}

variable "longhorn_disk_size_gib" {
  description = "Size in GiB of each dedicated Longhorn worker data disk."
  type        = number
  default     = 75
}
