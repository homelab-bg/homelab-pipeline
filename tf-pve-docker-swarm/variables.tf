# Node placement
variable "node_templates" {
  type        = map(number)
  description = "Cloud-init template VM ID per Proxmox node - each template lives on its matching node, so clones stay local"
  default = {
    pve1 = 924041
    pve2 = 924042
    pve3 = 924043
  }
}

variable "pve_nodes" {
  type        = list(string)
  description = "Nodes to round-robin VMs across, in order"
  default     = ["pve1", "pve2", "pve3"]

  validation {
    condition     = length(var.pve_nodes) > 0
    error_message = "pve_nodes must contain at least one node - an empty list breaks the round-robin index math in locals."
  }
}

# Networking
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
  description = "First three octets of the VM subnet, e.g. 192.168.0. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "cidr" {
  type    = number
  default = 24
}

variable "minio_s3_endpoint" {
  type        = string
  description = "MinIO S3 endpoint, e.g. https://minio.<lan_domain>:30000 - used only to read tf-pve-ceph's remote state (data source config can use variables, unlike the backend \"s3\" block above). No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

# Access
variable "authorized_github_users" {
  type        = list(string)
  description = "GitHub usernames whose public keys (via github.com/<user>.keys) get injected into every VM. Set via a gitignored .tfvars or TF_VAR_authorized_github_users - never as a committed default, since this list itself is an access-control decision."

  validation {
    condition     = length(var.authorized_github_users) > 0
    error_message = "authorized_github_users can't be empty - that would provision VMs nobody can SSH into."
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

# Cluster definition - one entry per node group (e.g. one per docker_role),
# each entry expands to node_count VMs distributed across pve_nodes.
variable "configuration" {
  description = "List of node groups to provision"
  type = list(object({
    vmid        = number
    ipaddr_id   = number
    docker_role = string
    node_count  = number
    sockets     = number
    cores       = number
    memory      = number
    disks = list(object({
      size    = number # GB, no unit suffix
      storage = string
      slot    = string # e.g. "virtio0", "virtio1" - no cloudinit entry needed, that's automatic now
    }))
  }))
  default = []

  validation {
    condition     = alltrue([for c in var.configuration : c.node_count > 0])
    error_message = "Every configuration entry needs node_count > 0."
  }
}

