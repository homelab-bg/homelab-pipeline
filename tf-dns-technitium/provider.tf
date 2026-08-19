provider "infisical" {
  host = var.infisical_host
  auth = {
    universal = {
      client_id     = var.infisical_client_id
      client_secret = var.infisical_client_secret
    }
  }
}

# Scoped read-only to this module's own folder - the "tf-dns-technitium-reader"
# machine identity's additional privilege only grants secrets:read on
# env prod, path /tf-dns-technitium (see homelab-pipeline README for how the
# Infisical project/folder structure is organised).
data "infisical_secrets" "this" {
  env_slug     = "prod"
  workspace_id = var.infisical_project_id
  folder_path  = "/tf-dns-technitium"
}

provider "technitium" {
  url   = data.infisical_secrets.this.secrets["TECHNITIUM_URL"].value
  token = data.infisical_secrets.this.secrets["TECHNITIUM_TOKEN"].value

  # Real cert now in place (was self-signed, causing a connection-reuse bug
  # where every 2nd+ request on a kept-alive connection failed with an empty
  # response - fixed itself once the real cert was installed, confirmed
  # 2026-08-10).
  skip_certificate_verification = false
}
