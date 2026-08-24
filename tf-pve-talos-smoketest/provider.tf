provider "proxmox" {
  endpoint = "https://pve1.${var.lan_domain}:8006/"
  insecure = false # PVE's default self-signed cert - flip to false if the API endpoint ever gets a real cert

  # api_token is intentionally NOT set here.
  # Export PROXMOX_VE_API_TOKEN before running terraform - the provider reads it automatically.

  ssh {
    username    = "root"
    private_key = file(var.ssh_private_key_path)
    agent       = false
  }
}

# No config needed at the provider level - every resource carries its own
# connection info via client_configuration/machine_secrets, unlike the
# proxmox provider's endpoint+token above.
provider "talos" {}
