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

variable "source_image_path" {
  description = "Pinned Ubuntu cloud image path"
  type        = string
  default     = "~/Downloads/ubuntu-24.04-server-cloudimg-amd64.img"

  validation {
    condition = try(
      filesha256(pathexpand(var.source_image_path)) == "6a81c37564db9b1ee84e141922625e1d7c5b389b99bb3c572e0243607d5bb4d2",
      false
    )
    error_message = "The Ubuntu image is missing or its SHA-256 does not match the pinned release."
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
