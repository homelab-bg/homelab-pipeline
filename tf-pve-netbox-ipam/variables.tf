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
  description = "Client ID for this module's scoped Infisical machine identity (read-only, /tf-pve-netbox-ipam folder). No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "infisical_client_secret" {
  type        = string
  sensitive   = true
  description = "Client secret for this module's scoped Infisical machine identity. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}
