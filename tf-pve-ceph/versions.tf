terraform {
  required_version = ">= 1.9"

  # No provider block needed - terraform_data and the ssh/remote-exec provisioner
  # are built into Terraform core. See main.tf for why: no Terraform provider
  # (bpg/proxmox included) exposes MDS creation, CephFS filesystem creation, or
  # CephX auth/capability management - those stay CLI-driven via remote-exec,
  # same shape as pkr-pve-templates/build.pkr.hcl wrapping `qm` over SSH.

  backend "s3" {
    bucket = "terraform-state"                # confirm this matches your actual bucket name
    key    = "homelab/ceph/terraform.tfstate" # distinct from every other repo's key - see README
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
