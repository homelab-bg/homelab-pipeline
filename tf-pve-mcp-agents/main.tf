data "http" "github_keys" {
  for_each = toset(var.authorized_github_users)
  url      = "https://github.com/${each.key}.keys"
}

locals {
  authorized_keys = flatten([
    for resp in data.http.github_keys : compact(split("\n", trimspace(resp.response_body)))
  ])
}

# Requests the next free address from the "reserved-60-99" general-purpose
# band (see homelab-pipeline IPAM.md's addressing-scheme table) rather than
# hand-picking a specific one - first real use of the programmatic-
# allocation path IPAM.md describes for workload modules, instead of the
# manual SOP every other host so far has used.
data "netbox_ip_ranges" "general_purpose" {
  filter {
    name  = "tag"
    value = "reserved-60-99"
  }
}

resource "netbox_available_ip_address" "mcp_agents" {
  ip_range_id = data.netbox_ip_ranges.general_purpose.ip_ranges[0].id
  status      = "active"
  description = "docker-mcp-agents - tf-pve-mcp-agents"
}

resource "proxmox_virtual_environment_vm" "mcp_agents" {
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
    type    = "host" # pve1/pve2/pve3 are identical hardware - see tf-pve-docker-green/main.tf for the same reasoning
  }

  memory {
    dedicated = var.vm.memory
  }

  scsi_hardware = "virtio-scsi-pci"
  boot_order    = ["virtio0"]

  # No explicit efi_disk block - full clone from a UEFI template, same
  # reasoning as tf-pve-docker-green/main.tf.
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

  # Confirmed live: on first boot, cloud-init can lose a race renaming the
  # interface to eth0 ("[busy] Error renaming mac=... from ens18 to eth0")
  # if DHCP/networkd brings ens18 up under its default name first - the
  # correct static netplan config (/etc/netplan/50-cloud-init.yaml) is
  # written either way, it just isn't applied to the live interface, which
  # falls back to DHCP. Not unique to this module - a known first-boot
  # timing issue, not a config bug. Fix: SSH in via the DHCP-assigned
  # address (check the DHCP pool, .101-.199) and run `sudo netplan apply` -
  # renames the interface and switches it to the real static address
  # immediately, no reboot needed.
  initialization {
    datastore_id = var.cloudinit_datastore
    interface    = "ide2"

    dns {
      domain  = var.searchdomain
      servers = var.nameservers
    }

    ip_config {
      ipv4 {
        address = netbox_available_ip_address.mcp_agents.ip_address # already "x.x.x.x/24" - NetBox returns full CIDR, matching what this expects directly
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
