provider "proxmox" {
  endpoint = "https://pve1.${var.lan_domain}:8006/"
  insecure = false
}

provider "infisical" {
  host = var.infisical_host
  auth = {
    universal = {
      client_id     = var.infisical_client_id
      client_secret = var.infisical_client_secret
    }
  }
}

# NETBOX_URL/NETBOX_API_TOKEN live in /shared, not a per-module folder - see
# tf-pve-netbox-ipam's own provider.tf for why. This module had no Infisical
# identity at all before now (no DNS records, no other secrets needed) - a
# new tf-pve-packer-reader identity was created for this, scoped only to
# /shared, rather than reusing an unrelated one.
data "infisical_secrets" "shared" {
  env_slug     = "prod"
  workspace_id = var.infisical_project_id
  folder_path  = "/shared"
}

provider "netbox" {
  server_url = data.infisical_secrets.shared.secrets["NETBOX_URL"].value
  api_token  = data.infisical_secrets.shared.secrets["NETBOX_API_TOKEN"].value
}

