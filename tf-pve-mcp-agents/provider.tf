provider "proxmox" {
  endpoint = "https://pve1.${var.lan_domain}:8006/"
  insecure = false

  # export PROXMOX_VE_API_TOKEN='terraform-prov@pve!tf-bpg=<secret from Bitwarden>' before running
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

# Scoped read-only to /tf-dns-technitium - that module owns the Technitium
# credential, this one is just a consumer (see homelab-pipeline SECRETS.md).
data "infisical_secrets" "technitium" {
  env_slug     = "prod"
  workspace_id = var.infisical_project_id
  folder_path  = "/tf-dns-technitium"
}

provider "technitium" {
  url   = data.infisical_secrets.technitium.secrets["TECHNITIUM_URL"].value
  token = data.infisical_secrets.technitium.secrets["TECHNITIUM_TOKEN"].value

  skip_certificate_verification = false
}

# NETBOX_URL/NETBOX_API_TOKEN live in /shared, not a per-module folder - see
# tf-pve-netbox-ipam's own provider.tf for why (shared across 2+ consumers
# with no meaningful per-module scope to narrow further).
data "infisical_secrets" "shared" {
  env_slug     = "prod"
  workspace_id = var.infisical_project_id
  folder_path  = "/shared"
}

provider "netbox" {
  server_url = data.infisical_secrets.shared.secrets["NETBOX_URL"].value
  api_token  = data.infisical_secrets.shared.secrets["NETBOX_API_TOKEN"].value
}
