data "http" "github_keys" {
  for_each = toset(var.authorized_github_users)
  url      = "https://github.com/${each.key}.keys"
}

locals {
  authorized_keys = flatten([
    for resp in data.http.github_keys : compact(split("\n", trimspace(resp.response_body)))
  ])
}

resource "proxmox_virtual_environment_vm" "packer_builder" {
  name        = "packer-builder"
  description = "Dedicated build host for Packer/libguestfs template builds - requires nested virtualization enabled on its node"
  vm_id       = 112    # adjust if this collides with anything existing
  node_name   = "pve1" # place on whichever node you're using for this
  tags        = ["terraform", "packer", "infra"]

  clone {
    vm_id = var.node_templates["pve1"] # keep in sync with node_name above
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    sockets = 1
    cores   = 2
    type    = "host" # required - exposes VT-x/AMD-V to the guest for libguestfs' internal appliance
  }

  memory {
    dedicated = 4096
  }

  scsi_hardware = "virtio-scsi-pci"
  boot_order    = ["virtio0"]

  disk {
    interface    = "virtio0"
    size         = 32
    datastore_id = "local-zfs"
  }

  network_device {
    model  = "virtio"
    bridge = "vmbr0"
  }

  initialization {
    datastore_id = var.cloudinit_datastore
    interface    = "ide2"

    dns {
      domain  = var.searchdomain
      servers = var.nameservers
    }

    ip_config {
      ipv4 {
        address = "${var.ipaddr_network}.112/${var.cidr}" # .112 matches vm_id above
        gateway = var.gateway
      }
    }

    user_account {
      username = "ubuntu"
      keys     = local.authorized_keys
    }
  }

  lifecycle {
    ignore_changes = [clone]
  }
}

