provider "proxmox" {
  endpoint = "https://pve1.${var.lan_domain}:8006/"
  insecure = false

  # export PROXMOX_VE_API_TOKEN='terraform-prov@pve!tf-bpg=<secret from Bitwarden>' before running
}
