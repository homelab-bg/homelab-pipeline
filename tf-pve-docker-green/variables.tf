# Networking - same LAN as every other module in this pipeline. docker1 sits
# on the existing subnet; lan.homelab.green (see dns.tf) is only the DNS zone
# this host's record lives in, not a separate network.
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

variable "minio_s3_endpoint" {
  type        = string
  description = "MinIO S3 endpoint, e.g. https://minio.<lan_domain>:30000 - used only to read tf-pve-ceph's remote state (data source config can use variables, unlike the backend \"s3\" block above). No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

# VM - a single fixed host, not a scalable group, so this skips the
# round-robin/for_each machinery tf-pve-docker-swarm needs for multiple nodes.
variable "vm" {
  type = object({
    vmid     = number
    name     = string
    ipaddr   = string
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
  description = "The docker-green host's placement and sizing. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

# DNS - single A record, no Failover/Weighted Round Robin app needed here:
# that mechanism exists to solve the multi-A-record fast-flux problem, which
# doesn't arise with exactly one target. See dns.tf.
variable "technitium_url" {
  type        = string
  description = "Technitium API URL, e.g. https://ns1.<lan_domain> - NO TRAILING SLASH (see tf-dns-technitium/variables.tf for why). No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "technitium_token" {
  type        = string
  sensitive   = true
  description = "Technitium API token, created out-of-band via the admin UI. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "docker_domain" {
  type        = string
  description = "Domain for the docker-green host itself (A record), e.g. docker1.lan.homelab.green - matches ansible-pve-docker-green's extra-vars. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "portainer_domain" {
  type        = string
  description = "Domain for Portainer's UI (CNAME onto docker_domain), e.g. portainer.lan.homelab.green - matches ansible-pve-docker-green's extra-vars. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "traefik_domain" {
  type        = string
  description = "Domain for the Traefik dashboard (CNAME onto docker_domain), e.g. traefik.lan.homelab.green - matches ansible-pve-docker-green's extra-vars. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "dns_record_ttl" {
  type        = number
  default     = 3600
  description = "TTL (seconds) for the docker-green A record. Long TTL is fine here - unlike the swarm's Failover records, there's nothing dynamic to avoid caching."
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
