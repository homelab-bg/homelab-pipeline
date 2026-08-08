data "http" "github_keys" {
  for_each = toset(var.authorized_github_users)
  url      = "https://github.com/${each.key}.keys"
}

locals {
  authorized_keys = flatten([
    for resp in data.http.github_keys : compact(split("\n", trimspace(resp.response_body)))
  ])
}

resource "proxmox_virtual_environment_vm" "test" {
  name      = "tf-test-01"
  node_name = "pve1"
  vm_id     = 100115 # first real VM ID in your range - adjust if this collides with anything existing

  clone {
    vm_id = 924041 # ubuntu-server-24.04-lts template on pve1
    full  = true
  }

  agent {
    enabled = true # requires qemu-guest-agent in the template for the IP output below to populate
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  scsi_hardware = "virtio-scsi-pci"
  boot_order    = ["virtio0"]

  disk {
    interface    = "virtio0"
    size         = 32
    datastore_id = "local-zfs"
  }

  efi_disk {
    datastore_id = "local-zfs"
    type         = "4m"
  }

  initialization {
    datastore_id = "local-zfs"

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      username = "steve"
      keys     = local.authorized_keys
    }
  }

  tags = ["terraform", "test"]
}

