# Talos is structurally different from the Ubuntu build in build.pkr.hcl:
# no offline customization step (qemu-guest-agent is already baked in via
# the pinned schematic, not installed post-download via virt-customize), no
# cloud-init drive (Talos config is applied post-boot via talosctl, not
# cloud-init - there's no SSH/user-account surface on a Talos node at all),
# and a couple of hardware settings Talos's own docs call out as required
# (disk cache=writethrough, ballooning explicitly disabled) that the Ubuntu
# build doesn't need. Also, unlike Ubuntu, Talos's binaries hard-require
# x86-64-v2 microarchitecture support - Proxmox's default kvm64 CPU type
# doesn't expose it, which produces an immediate, deterministic boot loop
# ("This program can only be run on AMD64 processors with v2
# microarchitecture support" -> kernel panic on PID 1 exit, confirmed live
# via serial console). --cpu host (see build.pkr.hcl's comment for why it's
# safe cluster-wide) exceeds v2 comfortably and matches the Ubuntu build for
# uniformity. Same per-target idempotency/failure-isolation pattern as
# build.pkr.hcl's deploy_blocks otherwise - see that file's comment for the
# full reasoning, not repeated here.
locals {
  talos_image_file  = "talos-${var.talos_version}-nocloud-amd64.qcow2"
  talos_image_url   = "https://factory.talos.dev/image/${var.talos_schematic_id}/${var.talos_version}/nocloud-amd64.qcow2"
  talos_local_image = "${var.local_staging_dir}/${local.talos_image_file}"
  # Provenance stamp (see talos.pkrvars.hcl's targets comment) - every value
  # here is already known at HCL-eval time, no runtime shell computation
  # needed, unlike build.pkr.hcl's build_sha which can only exist after the
  # image is actually downloaded.
  talos_build_date = formatdate("YYYY-MM-DD", timestamp())

  talos_deploy_blocks = [for t in var.targets : <<-EOT
    echo "=== Deploying to ${t.pve_node} (${t.pve_node}.${var.lan_domain}), vmid ${t.vmid} ==="
    if scp ${local.ssh_opts} ${local.talos_local_image} root@${t.pve_node}.${var.lan_domain}:/var/lib/vz/template/iso/${local.talos_image_file} && \
       ssh ${local.ssh_opts} root@${t.pve_node}.${var.lan_domain} '
         if qm status ${t.vmid} >/dev/null 2>&1; then
           if qm config ${t.vmid} | grep -q "^template: 1"; then
             echo "vmid ${t.vmid} exists as a template - destroying before rebuild" &&
             qm destroy ${t.vmid} --purge 1
           else
             echo "refusing to touch vmid ${t.vmid}: exists but is not a template" >&2
             exit 1
           fi
         fi &&
         qm create ${t.vmid} --name ${var.template_name} --memory 2048 --balloon 0 --cpu host --net0 virtio,bridge=${var.bridge} --scsihw virtio-scsi-pci --machine q35 &&
         qm set ${t.vmid} --virtio0 ${var.storage_pool}:0,import-from=/var/lib/vz/template/iso/${local.talos_image_file},cache=writethrough &&
         qm set ${t.vmid} --boot order=virtio0 &&
         qm set ${t.vmid} --serial0 socket --vga serial0 &&
         qm set ${t.vmid} --agent enabled=1 &&
         qm set ${t.vmid} --bios ${var.bios} --efidisk0 ${var.storage_pool}:1,efitype=4m,pre-enrolled-keys=0 &&
         qm set ${t.vmid} --tags packer,talos,${var.talos_version},built-${local.talos_build_date} &&
         qm set ${t.vmid} --description "Talos ${var.talos_version} - schematic ${var.talos_schematic_id} - built ${local.talos_build_date} via pkr-pve-templates/talos-build.pkr.hcl" &&
         qm template ${t.vmid}
       '; then
      echo "=== ${t.pve_node}: OK ==="
    else
      echo "=== ${t.pve_node}: FAILED ==="
      FAILED_NODES="$FAILED_NODES ${t.pve_node}"
    fi
  EOT
  ]
  talos_deploy_script = join("\n", local.talos_deploy_blocks)
}

build {
  sources = ["source.null.talos_template"]

  # 1. Download the Image Factory image locally - no offline customization
  #    needed, unlike the Ubuntu build's virt-customize step.
  provisioner "shell-local" {
    inline = [
      "mkdir -p ${var.local_staging_dir}",
      "wget -q -O ${local.talos_local_image} ${local.talos_image_url}",
    ]
  }

  # 2. Upload to each target node's storage, create the VM shell, import the
  #    disk, configure firmware + agent channel, and convert to template.
  provisioner "shell-local" {
    inline = [<<-EOT
      FAILED_NODES=""
      ${local.talos_deploy_script}
      if [ -n "$FAILED_NODES" ]; then
        echo "Deployment failed for:$FAILED_NODES"
        exit 1
      fi
    EOT
    ]
  }
}
