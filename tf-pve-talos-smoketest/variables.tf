variable "lan_domain" {
  type        = string
  description = "Internal LAN domain suffix, e.g. pve1.<lan_domain>. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "ssh_private_key_path" {
  type        = string
  description = "Path to the SSH private key for root access to the PVE nodes. The bpg/proxmox provider's own SSH client (used here for snippet file management - proxmox_virtual_environment_file - Proxmox's API has no direct upload path for the snippets content type) is separate from Terraform's provisioner connections and from your system SSH: it doesn't read ~/.ssh/config and doesn't reliably pick up ssh-agent, confirmed live. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}
