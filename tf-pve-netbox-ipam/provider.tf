provider "infisical" {
  host = var.infisical_host
  auth = {
    universal = {
      client_id     = var.infisical_client_id
      client_secret = var.infisical_client_secret
    }
  }
}

# NETBOX_URL/NETBOX_API_TOKEN moved to /shared - tf-pve-mcp-agents also needs them now
# (to request its own IP), and this credential has no meaningful per-module scope to
# narrow further beyond "can talk to NetBox" (same reasoning as ROUTE53_BAUER_* moving
# to /shared once it had 2 consumers - see SECRETS.md).
data "infisical_secrets" "shared" {
  env_slug     = "prod"
  workspace_id = var.infisical_project_id
  folder_path  = "/shared"
}

provider "netbox" {
  server_url = data.infisical_secrets.shared.secrets["NETBOX_URL"].value
  api_token  = data.infisical_secrets.shared.secrets["NETBOX_API_TOKEN"].value
}
