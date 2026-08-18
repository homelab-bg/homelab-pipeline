variable "lan_domain" {
  type        = string
  description = "Internal LAN domain suffix, e.g. pve1.<lan_domain>. No default - supply via a gitignored local.auto.tfvars (see local.auto.tfvars.example)."
}

variable "authorized_github_users" {
  type        = list(string)
  description = "GitHub usernames whose public keys (via github.com/<user>.keys) get injected into the test VM. Set via a gitignored local.auto.tfvars or TF_VAR_authorized_github_users - never as a committed default."

  validation {
    condition     = length(var.authorized_github_users) > 0
    error_message = "authorized_github_users can't be empty - that would provision a VM nobody can SSH into."
  }
}

