# Reads tf-pve-ceph's outputs (mon_hosts, fs_name, fsid) - read-only, so this never
# participates in this config's own destroy plan and doesn't reintroduce the coupling
# tf-pve-ceph's separate state is there to avoid. See tf-pve-ceph section in the
# top-level README for the full rationale.
data "terraform_remote_state" "ceph" {
  backend = "s3"
  config = {
    bucket = "terraform-state"
    key    = "homelab/ceph/terraform.tfstate"
    region = "us-east-1"

    endpoints = {
      s3 = var.minio_s3_endpoint
    }

    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
  }
}

output "cephfs_mon_hosts" {
  description = "From tf-pve-ceph - feed into ansible-pve-docker-swarm's extra-vars.yml (cephfs_mon_hosts)"
  value       = data.terraform_remote_state.ceph.outputs.mon_hosts
}

output "cephfs_name" {
  description = "From tf-pve-ceph - feed into ansible-pve-docker-swarm's extra-vars.yml (cephfs_name)"
  value       = data.terraform_remote_state.ceph.outputs.fs_name
}
