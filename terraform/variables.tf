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

# Ubuntu 26.04 (resolute) server cloud image, serial 20261016, from
# https://cloud-images.ubuntu.com/releases/26.04/release-20261016/
# SHA-256 taken from that release's GPG-signed SHA256SUMS.
variable "source_image_path" {
  description = "Pinned Ubuntu cloud image path"
  type        = string
  default     = "~/Downloads/ubuntu-26.04/resolute-server-cloudimg-amd64.img"

  validation {
    condition = try(
      filesha256(pathexpand(var.source_image_path)) == "5645d0318ad21f643ebb1ac4567514620e9893380b07b0201fda163baa5b7eb5",
      false
    )
    error_message = "The Ubuntu image is missing or its SHA-256 does not match the pinned release."
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
