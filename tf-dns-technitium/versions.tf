terraform {
  required_version = ">= 1.9"

  required_providers {
    technitium = {
      source  = "kevynb/technitium"
      version = "0.4.0"
    }
    infisical = {
      source  = "infisical/infisical"
      version = "0.19.24"
    }
  }

  backend "s3" {
    bucket = "terraform-state"               # confirm this matches your actual bucket name
    key    = "homelab/dns/terraform.tfstate" # distinct from every other repo's key
    region = "us-east-1"

    # endpoints.s3 is intentionally NOT set here - backend blocks can't reference
    # variables, so the internal MinIO endpoint is supplied at init time via
    # `terraform init -backend-config=backend.local.hcl` (see backend.local.hcl.example).

    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
  }
}
