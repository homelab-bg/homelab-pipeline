data "http" "github_keys" {
  for_each = toset(var.authorized_github_users)
  url      = "https://github.com/${each.key}.keys"
}

locals {
  authorized_keys = flatten([
    for resp in data.http.github_keys : compact(split("\n", trimspace(resp.response_body)))
  ])

  serverconfig = [
    for srv in var.configuration : [
      for i in range(1, srv.node_count + 1) : {
        vmid        = srv.vmid + i
        ipaddr      = "${var.ipaddr_network}.${srv.ipaddr_id + i}"
        name        = "docker-${srv.docker_role}-${srv.vmid + i}"
        target_node = var.pve_nodes[(i - 1) % length(var.pve_nodes)]
        sockets     = srv.sockets
        cores       = srv.cores
        memory      = srv.memory
        disks       = srv.disks
      }
    ]
  ]

  instances = { for server in flatten(local.serverconfig) : server.name => server }
}

resource "proxmox_virtual_environment_vm" "docker" {
  for_each = local.instances

  name        = each.value.name
  description = "${each.value.name} - cloned from template ${var.node_templates[each.value.target_node]} on ${each.value.target_node}, managed by Terraform"
  vm_id       = each.value.vmid
  node_name   = each.value.target_node
  tags        = ["terraform", "docker", each.value.target_node]

  clone {
    vm_id = var.node_templates[each.value.target_node] # same node as target - no cross-node clone
    full  = true
  }

  agent {
    enabled = true # graceful shutdown + live disk resize; also avoids a known kernel-panic-on-resize issue with Ubuntu cloud images
  }

  cpu {
    sockets = each.value.sockets
    cores   = each.value.cores
  }

  memory {
    dedicated = each.value.memory
  }

  scsi_hardware = "virtio-scsi-pci"
  boot_order    = ["virtio0"]

  operating_system {
    type = "l26"
  }

  vga {
    type = "serial0"
  }

  serial_device {}

  dynamic "disk" {
    for_each = each.value.disks
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
        address = "${each.value.ipaddr}/${var.cidr}"
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

