# Targets
variable "targets" {
  type = list(object({
    pve_node = string
    vmid     = number
  }))
  description = "Proxmox nodes to deploy the built template to. The image is downloaded and customized once, then deployed to each of these."
}

variable "lan_domain" {
  type        = string
  description = "DNS suffix appended to each target's pve_node to form its SSH host, e.g. pve1.<lan_domain>. No default - supply via a gitignored *.auto.pkrvars.hcl (see local.auto.pkrvars.hcl)."
}

variable "template_name" {
  type = string
}

# Image source
variable "ubuntu_codename" {
  type        = string
  description = "Matches the path on cloud-images.ubuntu.com - e.g. resolute (26.04), noble (24.04)"
}

variable "ubuntu_version" {
  type        = string
  description = "e.g. 26.04"
}

# Hardware
variable "storage_pool" {
  type    = string
  default = "local-zfs"
}

variable "bridge" {
  type    = string
  default = "vmbr0"
}

variable "bios" {
  type        = string
  default     = "ovmf"
  description = "ovmf (UEFI) - defaulting to UEFI per current standardization; set to seabios to validate the BIOS-compat theory later"
}

# Local staging (on the machine running Packer, e.g. jump)
variable "local_staging_dir" {
  type    = string
  default = "/tmp/packer-build"
}


