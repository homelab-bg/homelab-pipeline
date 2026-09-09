# Networking - same LAN as every other module in this pipeline.
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

variable "cidr" {
  type    = number
  default = 24
}

# VM - a single fixed host, not a scalable group.
variable "vm" {
  type = object({
    vmid     = number
    name     = string
    node     = string
    template = number
    sockets  = number
    cores    = number
    memory   = number
    disks = list(object({
      size    = number # GB, no unit suffix
      storage = string
      slot    = string # e.g. "virtio0", "virtio1"
    }))
  })
  description = "The docker-mcp-agents host's placement and sizing - no ipaddr field, its IP is requested from NetBox at apply time (see main.tf). No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
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
  description = "Client ID for this module's scoped Infisical machine identity (read-only, /tf-dns-technitium and /shared). No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "infisical_client_secret" {
  type        = string
  sensitive   = true
  description = "Client secret for this module's scoped Infisical machine identity. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

# DNS - one A record for the host itself, plus one per MCP service hostname
# (all pointing at the same VM - see dns.tf for why no CNAME chain is needed).
variable "docker_mcp_agents_domain" {
  type        = string
  description = "Domain for the docker-mcp-agents host itself (A record), e.g. docker-mcp-agents.lan.homelab.green. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "ha_mcp_domain" {
  type        = string
  description = "Domain for the ha-mcp service (A record), e.g. ha-mcp.lan.homelab.green. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "unifi_network_mcp_domain" {
  type        = string
  description = "Domain for the unifi-network-mcp service (A record). No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "unifi_protect_mcp_domain" {
  type        = string
  description = "Domain for the unifi-protect-mcp service (A record). No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "unifi_access_mcp_domain" {
  type        = string
  description = "Domain for the unifi-access-mcp service (A record). No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "truenas_mcp_domain" {
  type        = string
  description = "Domain for the truenas-mcp service (A record). No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "dns_record_ttl" {
  type        = number
  default     = 3600
  description = "TTL (seconds) for this module's A records."
}

# Access
variable "authorized_github_users" {
  type        = list(string)
  description = "GitHub usernames whose public keys (via github.com/<user>.keys) get injected into the VM. Set via a gitignored .tfvars or TF_VAR_authorized_github_users - never as a committed default, since this list itself is an access-control decision."

  validation {
    condition     = length(var.authorized_github_users) > 0
    error_message = "authorized_github_users can't be empty - that would provision a VM nobody can SSH into."
  }
}

variable "ciuser" {
  type    = string
  default = "ubuntu"
}

variable "cipassword" {
  type        = string
  default     = null
  sensitive   = true
  description = "Optional cloud-init console password. Leave null for SSH-key-only auth (recommended) - override via TF_VAR_cipassword if you need one, never as a committed default."
}

variable "cloudinit_datastore" {
  type    = string
  default = "local-zfs"
}
