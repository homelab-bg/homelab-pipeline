variable "infisical_host" {
  type        = string
  description = "Self-hosted Infisical instance URL. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "infisical_project_id" {
  type        = string
  description = "Infisical project ID for homelab-pipeline. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "infisical_client_id" {
  type        = string
  description = "Client ID for this module's scoped Infisical machine identity (read-only, /tf-dns-technitium folder). No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "infisical_client_secret" {
  type        = string
  sensitive   = true
  description = "Client secret for this module's scoped Infisical machine identity. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "record_ttl" {
  type        = number
  default     = 3600
  description = "TTL (seconds) for the secrets host A record."
}

# The LXC itself is out of scope for this module - it's a manually-created
# (Proxmox community-scripts) container, not Terraform-provisioned, unlike
# every VM elsewhere in this pipeline. This module only formalizes its DNS
# record under IaC, matching how every other record in this project is
# Terraform-managed regardless of how the underlying host was provisioned.
variable "secrets_domain" {
  type        = string
  description = "Domain for the key-infra secrets host, e.g. secrets.lan.bauer.com.au. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "secrets_ipaddr" {
  type        = string
  description = "IP address of the manually-provisioned secrets LXC. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}
