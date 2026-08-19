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
  description = "TTL (seconds) applied to every record this module manages - technitium_record has no default of its own, ttl is a required attribute."
}
