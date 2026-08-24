# First Terraform-managed LXC in this project - every existing tf-pve-*
# module provisions a VM (cloned from a Packer template). The two existing
# LXCs (secrets, the GH Actions runner) were both provisioned out-of-band via
# community-scripts (ct/docker.sh) with no matching tf-pve-* module at all -
# this is a deliberate departure from that, to avoid a repeat of the
# packer-builder reconciliation problem (undocumented host state, silent
# fork drift) for a new service. See homelab-pipeline's README for the full
# reasoning, and the plan to bring secrets/the GH runner under this same
# approach later.
#
# Container spec (Debian 13, unprivileged, features.nesting) matches
# ct/docker.sh's own baseline - confirmed by reading the actual script
# (community-scripts/ProxmoxVE, ct/docker.sh) rather than assumed - except
# sized up (2 vCPU/4GB/20GB vs. its 2 vCPU/2GB/4GB defaults) for
# NetBox+Postgres+Redis running together. Docker itself is installed the
# same way ansible-pve-docker-green already does it (docker-dependencies.yml
# reused, not re-derived from the community script), not by the script.

data "http" "github_keys" {
  for_each = toset(var.authorized_github_users)
  url      = "https://github.com/${each.key}.keys"
}

locals {
  authorized_keys = flatten([
    for resp in data.http.github_keys : compact(split("\n", trimspace(resp.response_body)))
  ])
  vmid     = 117 # matches the last octet of ipaddr below, same convention as everything else in this project
  ipaddr   = "172.16.0.17"
  hostname = "netbox"
}

# Debian 13 CT template - real filename/checksum confirmed live via `pveam
# available`/the cached apl-info catalog on pve1, not guessed. Bump
# deliberately (matching this project's pin-everything discipline) when a
# newer point release is needed - re-derive via the same commands.
resource "proxmox_download_file" "debian13_template" {
  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = "pve1"

  url                = "http://download.proxmox.com/images/system/debian-13-standard_13.6-1_amd64.tar.zst"
  checksum           = "4c0c27ca6ceab5ef0b84db57825a00f26157ef1854bafe97297813e1cbe8ecb8cc9c453cab6b3b0efe1ba193a50c47ece1e41d950e411b8730b835b71e9e754b"
  checksum_algorithm = "sha512"
}

resource "proxmox_virtual_environment_container" "netbox" {
  node_name = "pve1"
  vm_id     = local.vmid

  unprivileged = true

  operating_system {
    template_file_id = proxmox_download_file.debian13_template.id
    type             = "debian"
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = "local-zfs"
    size         = 20
  }

  # nesting is required for Docker/containerd to run inside the LXC at all -
  # ct/docker.sh's shared build.func framework sets this implicitly; it's
  # explicit here since it's easy to miss if only copying the visible
  # var_cpu/var_ram/var_disk numbers from the script.
  features {
    nesting = true
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  initialization {
    hostname = local.hostname

    ip_config {
      ipv4 {
        address = "${local.ipaddr}/24"
        gateway = var.gateway
      }
    }

    dns {
      domain  = var.searchdomain
      servers = var.nameservers
    }

    # Root-only SSH, no separate user account - matches the existing
    # secrets LXC's pattern (see ~/.ssh/config's own comment on that host).
    # Containers' user_account has no username field at all (unlike VMs') -
    # confirmed via the provider schema - it configures root directly.
    user_account {
      keys = local.authorized_keys
    }
  }

  tags = ["terraform", "netbox", "docker"]
}
