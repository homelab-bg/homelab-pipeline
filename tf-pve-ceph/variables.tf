variable "lan_domain" {
  type        = string
  description = "Internal LAN domain suffix, e.g. pve1.<lan_domain>. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "pve_nodes" {
  type        = list(string)
  description = "PVE nodes to create an MDS on (foundational/shared - reused by whichever filesystem(s) get created against them)"
  default     = ["pve1", "pve2", "pve3"]

  validation {
    condition     = length(var.pve_nodes) > 0
    error_message = "pve_nodes must contain at least one node."
  }
}

variable "fs_name" {
  type        = string
  description = "CephFS filesystem name. No default, deliberately - use a distinct test identity (e.g. \"cephfs-test\") while iterating, and only point this at the real \"cephfs\" once, deliberately, when testing is done (see README - Testing vs. production)."

  validation {
    condition     = length(var.fs_name) > 0
    error_message = "fs_name can't be empty."
  }
}

variable "mon_hosts" {
  type        = list(string)
  description = "Ceph mon addresses, e.g. [\"192.168.0.201\", ...] - not created by this module, just surfaced for consumers. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "ssh_private_key_path" {
  type        = string
  description = "Path to the SSH private key for root access to the PVE nodes. remote-exec provisioners use Terraform's own SSH client, not the OpenSSH CLI - they don't read ~/.ssh/config and don't reliably pick up ssh-agent, so this needs to be explicit. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "fsid" {
  type        = string
  description = "Ceph cluster fsid (from /etc/pve/ceph.conf on any PVE node) - not created by this module, just surfaced for consumers. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}
