provider "proxmox" {
  endpoint = "https://pve1.${var.lan_domain}:8006/"
  insecure = false
}

