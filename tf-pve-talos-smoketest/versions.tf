terraform {
  required_version = ">= 1.9"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.111.1" # https://registry.terraform.io/providers/bpg/proxmox — bump deliberately, provider is still 0.x
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0" # https://registry.terraform.io/providers/siderolabs/talos — bump deliberately
    }
  }

  backend "s3" {
    # CONFIRM this matches the exact bucket name you created in MinIO
    bucket = "terraform-state"
    key    = "homelab/talos-smoketest/terraform.tfstate"
    region = "us-east-1" # dummy value — required by the backend schema, unused by MinIO

    # endpoints.s3 is intentionally NOT set here - backend blocks can't reference
    # variables, so the internal MinIO endpoint is supplied at init time via
    # `terraform init -backend-config=backend.local.hcl` (see backend.local.hcl.example).

    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true

    # Access key / secret key are intentionally NOT set here.
    # Export AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY before running terraform —
    # the S3 backend reads them automatically, same pattern as the provider token below.
  }
}
