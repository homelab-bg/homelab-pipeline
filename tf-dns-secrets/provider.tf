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
# credential, this one is just a consumer (see homelab-pipeline README).
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
