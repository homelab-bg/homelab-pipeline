provider "infisical" {
  host = var.infisical_host
  auth = {
    universal = {
      client_id     = var.infisical_client_id
      client_secret = var.infisical_client_secret
    }
  }
}

# Scoped read-only to this module's own folder - the "tf-pve-netbox-ipam-reader"
# machine identity's additional privilege only grants secrets:read on
# env prod, path /tf-pve-netbox-ipam (see homelab-pipeline SECRETS.md for how
# the Infisical project/folder structure is organised).
data "infisical_secrets" "this" {
  env_slug     = "prod"
  workspace_id = var.infisical_project_id
  folder_path  = "/tf-pve-netbox-ipam"
}

provider "netbox" {
  server_url = data.infisical_secrets.this.secrets["NETBOX_URL"].value
  api_token  = data.infisical_secrets.this.secrets["NETBOX_API_TOKEN"].value
}
