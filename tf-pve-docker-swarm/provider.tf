provider "proxmox" {
  endpoint = "https://pve1.${var.lan_domain}:8006/"
  insecure = false

  # export PROXMOX_VE_API_TOKEN='terraform-prov@pve!tf-bpg=<secret from Bitwarden>' before running
}

provider "technitium" {
  url   = var.technitium_url
  token = var.technitium_token

  # Real cert now in place - see tf-dns-technitium/provider.tf for history.
  skip_certificate_verification = false
}
