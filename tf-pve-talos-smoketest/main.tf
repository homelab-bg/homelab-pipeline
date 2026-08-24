# Validates the ISO-attach static-IP mechanism for Talos before building out
# a real cluster module: a single control-plane node, cloned from the
# talos-1.13 template, gets its machine config (with a static IP baked into
# machine.network.interfaces) delivered via a Proxmox cloud-init snippet at
# clone time - Talos's "nocloud" platform reads it the same way it would
# read a hand-built NoCloud ISO, no DHCP/talosctl-apply-config dance needed
# (see homelab-pipeline's README, pkr-pve-templates section, for why Talos
# has no cloud-init *user* surface but does support this for machine config).
# Single control-plane node is enough to prove the mechanism and produce a
# working (if not HA) kubeconfig - the real multi-node module is next once
# this is confirmed live.

locals {
  cluster_name     = "k8s-smoketest"
  node_hostname    = "k8s-smoketest1"
  node_ip          = "172.16.0.250"
  node_cidr        = "${local.node_ip}/24"
  gateway          = "172.16.0.1"
  nameservers      = ["172.16.0.2", "172.16.0.3", "172.16.0.4"]
  cluster_endpoint = "https://${local.node_ip}:6443"
  # Matches pkr-pve-templates/talos.pkrvars.hcl's talos_version - not derived
  # automatically (that file lives in a different module with its own
  # lifecycle), so re-check it there if this ever drifts.
  talos_version = "v1.13.9"
}

resource "talos_machine_secrets" "this" {
  talos_version = local.talos_version
}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = local.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  machine_type     = "controlplane"
  talos_version    = local.talos_version

  # Static network config, strategic-merged into the generated machine
  # config - this (not cloud-init, Talos has no cloud-init user surface) is
  # what actually lands on disk via the snippet below.
  #
  # "eth0" is confirmed correct for this template's virtio NIC (checked live
  # via the guest agent's network-get-interfaces, MAC matched net0) - Talos's
  # minimal init doesn't apply systemd's predictable-network-interface-names
  # scheme the way Ubuntu does.
  config_patches = [
    yamlencode({
      machine = {
        network = {
          # No explicit hostname here on purpose - setting it in the machine
          # config conflicts with Talos's nocloud platform's own hostname
          # handling ("static hostname is already set in v1alpha1 config" -
          # confirmed live via serial console). The real hostname is
          # delivered via controlplane_metadata's local-hostname field below
          # instead - the standard NoCloud metadata mechanism Talos's
          # nocloud platform reads for this, which doesn't conflict.
          interfaces = [
            {
              interface = "eth0"
              addresses = [local.node_cidr]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = local.gateway
                }
              ]
            }
          ]
          nameservers = local.nameservers
        }
      }
    })
  ]
}

resource "proxmox_virtual_environment_file" "controlplane_config" {
  content_type = "snippets"
  datastore_id = "nfs" # shared across all 3 nodes, not node-local like local-zfs - see homelab-ci's README
  node_name    = "pve1"

  source_raw {
    data      = data.talos_machine_configuration.controlplane.machine_configuration
    file_name = "${local.node_hostname}-controlplane.yaml"
  }
}

# Proxmox's own auto-generated meta-data only ever carries a random
# instance-id, no local-hostname (confirmed live via isoinfo against the
# generated ISO) - without this, Talos's nocloud platform falls back to its
# own auto-generated name (e.g. "talos-sid-61k"). local-hostname is the
# standard NoCloud metadata field Talos's nocloud platform reads for this -
# setting hostname directly in the machine config instead (config_patches
# above) is what caused the "static hostname is already set in v1alpha1
# config" validation failure fixed earlier, since that conflicts with the
# platform's own hostname handling. This is the correct, non-conflicting path.
resource "proxmox_virtual_environment_file" "controlplane_metadata" {
  content_type = "snippets"
  datastore_id = "nfs"
  node_name    = "pve1"

  source_raw {
    data      = <<-EOT
      instance-id: ${local.node_hostname}
      local-hostname: ${local.node_hostname}
    EOT
    file_name = "${local.node_hostname}-metadata.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "controlplane" {
  name      = local.node_hostname
  node_name = "pve1"
  vm_id     = 100116 # next after tf-pve-template-smoketest's 100115

  clone {
    vm_id = 901131 # talos-1.13 template on pve1
    full  = true
  }

  agent {
    enabled = true # qemu-guest-agent is baked into the template's schematic
  }

  cpu {
    cores = 2
    type  = "host" # explicit, not left to the provider default - see build.pkr.hcl/tf-pve-template-smoketest for why (pve1/pve2/pve3 confirmed identical hardware)
  }

  memory {
    dedicated = 4096 # more than the template's 2048 - etcd/kubelet/apiserver need real headroom, even for a smoketest
  }

  scsi_hardware = "virtio-scsi-pci"
  boot_order    = ["virtio0"]

  disk {
    interface    = "virtio0"
    size         = 32 # bumped from the template's ~4GB - k8s images/etcd data need real room
    datastore_id = "local-zfs"
  }

  efi_disk {
    datastore_id = "local-zfs"
    type         = "4m"
  }

  initialization {
    datastore_id = "local-zfs"
    # No ip_config block - Talos doesn't consume cloud-init's network-config
    # at all, only its own machine config (delivered via user_data_file_id
    # below), so setting one here would just be inert clutter.
    user_data_file_id = proxmox_virtual_environment_file.controlplane_config.id
    meta_data_file_id = proxmox_virtual_environment_file.controlplane_metadata.id
  }

  tags = ["terraform", "test", "talos"]
}

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.node_ip
  endpoint             = local.node_ip

  depends_on = [proxmox_virtual_environment_vm.controlplane]
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.node_ip
  endpoint             = local.node_ip

  depends_on = [talos_machine_bootstrap.this]
}
