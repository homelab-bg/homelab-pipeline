variable "node_templates" {
  type        = map(number)
  description = "Cloud-init template VM ID per Proxmox node"
  default = {
    pve1 = 924041
    pve2 = 924042
    pve3 = 924043
  }
}

variable "lan_domain" {
  type        = string
  description = "Internal LAN domain suffix, e.g. pve1.<lan_domain>. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "searchdomain" {
  type        = string
  description = "DNS search domain pushed via cloud-init. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "nameservers" {
  type        = list(string)
  description = "DNS servers pushed via cloud-init. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "gateway" {
  type        = string
  description = "IPv4 gateway pushed via cloud-init. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "ipaddr_network" {
  type        = string
  description = "First three octets of this VM's subnet, e.g. 192.168.0. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "cidr" {
  type    = number
  default = 24
}

variable "cloudinit_datastore" {
  type    = string
  default = "local-zfs"
}

variable "authorized_github_users" {
  type        = list(string)
  description = "GitHub usernames whose public keys get injected into this VM. Set via a gitignored .tfvars or TF_VAR_authorized_github_users - never as a committed default."

  validation {
    condition     = length(var.authorized_github_users) > 0
    error_message = "authorized_github_users can't be empty - that would provision a VM nobody can SSH into."
  }
}

