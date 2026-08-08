terraform {
  required_version = ">= 1.9"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.111.1"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.6"
    }
  }

  backend "s3" {
    bucket = "terraform-state"                          # confirm this matches your actual bucket name
    key    = "homelab/packer-builder/terraform.tfstate" # distinct from the docker-swarm repo's key
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

