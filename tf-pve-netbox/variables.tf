variable "lan_domain" {
  type        = string
  description = "Internal LAN domain suffix, e.g. pve1.<lan_domain>. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "authorized_github_users" {
  type        = list(string)
  description = "GitHub usernames whose public keys (via github.com/<user>.keys) get injected as root's authorized_keys - root-only SSH, no separate user account, matching the existing secrets LXC. No default - supply via a gitignored local.auto.tfvars or TF_VAR_authorized_github_users - never as a committed default."

  validation {
    condition     = length(var.authorized_github_users) > 0
    error_message = "authorized_github_users can't be empty - that would provision a container nobody can SSH into."
  }
}

variable "searchdomain" {
  type        = string
  description = "DNS search domain pushed to the container. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "nameservers" {
  type        = list(string)
  description = "DNS servers pushed to the container. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "gateway" {
  type        = string
  description = "IPv4 gateway for the container. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "netbox_domain" {
  type        = string
  description = "FQDN for the NetBox A record, e.g. ipam.lan.example.internal. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "dns_record_ttl" {
  type        = number
  default     = 3600
  description = "TTL (seconds) for the NetBox A record. Long TTL is fine - nothing dynamic to avoid caching."
}

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
