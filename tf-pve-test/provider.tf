provider "proxmox" {
  endpoint = "https://pve1.${var.lan_domain}:8006/"
  insecure = false # PVE's default self-signed cert - flip to false if the API endpoint ever gets a real cert

  # api_token is intentionally NOT set here.
  # Export PROXMOX_VE_API_TOKEN before running terraform - the provider reads it automatically.
  # Format: "terraform-prov@pve!tf-bpg=<secret-from-bitwarden>"
}

