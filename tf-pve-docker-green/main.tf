data "http" "github_keys" {
  for_each = toset(var.authorized_github_users)
  url      = "https://github.com/${each.key}.keys"
}

locals {
  authorized_keys = flatten([
    for resp in data.http.github_keys : compact(split("\n", trimspace(resp.response_body)))
  ])
}

resource "proxmox_virtual_environment_vm" "docker" {
  name        = var.vm.name
  description = "${var.vm.name} - cloned from template ${var.vm.template} on ${var.vm.node}, managed by Terraform"
  vm_id       = var.vm.vmid
  node_name   = var.vm.node
  tags        = ["terraform", "docker", var.vm.node]

  clone {
    vm_id = var.vm.template
    full  = true
  }

  agent {
    enabled = true # graceful shutdown + live disk resize; also avoids a known kernel-panic-on-resize issue with Ubuntu cloud images
  }

  cpu {
    sockets = var.vm.sockets
    cores   = var.vm.cores
  }

  memory {
    dedicated = var.vm.memory
  }

  scsi_hardware = "virtio-scsi-pci"
  boot_order    = ["virtio0"]

  # No explicit efi_disk block - the template is UEFI (bios=ovmf, see
  # pkr-pve-templates), but this is a full clone, not a from-scratch build,
  # so the EFI disk clones onto the same storage as the source template
  # (local-zfs) without needing to be declared. Confirmed live against
  # tf-pve-docker-swarm's VMs, which use this exact pattern.
  operating_system {
    type = "l26"
  }

  vga {
    type = "serial0"
  }

  serial_device {}

  dynamic "disk" {
    for_each = var.vm.disks
    content {
      interface    = disk.value.slot
      size         = disk.value.size
      datastore_id = disk.value.storage
    }
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
        address = "${var.vm.ipaddr}/${var.cidr}"
        gateway = var.gateway
      }
    }

    user_account {
      username = var.ciuser
      password = var.cipassword
      keys     = local.authorized_keys
    }
  }

  lifecycle {
    ignore_changes = [clone] # clone is a create-time-only operation; don't let it generate diffs on later applies
  }
}
