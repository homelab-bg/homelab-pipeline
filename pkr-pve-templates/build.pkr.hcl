locals {
  image_file  = "${var.ubuntu_codename}-server-cloudimg-amd64.img"
  image_url   = "https://cloud-images.ubuntu.com/releases/${var.ubuntu_codename}/release/ubuntu-${var.ubuntu_version}-server-cloudimg-amd64.img"
  local_image = "${var.local_staging_dir}/${local.image_file}"
  ssh_opts    = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes"

  # One deploy block per target, unrolled at plan time. Each is independent —
  # a failure on one node doesn't stop the others, and failures are collected
  # into $FAILED_NODES for the final pass/fail check.
  #
  # Before creating, checks whether vmid already exists: if absent, proceeds
  # straight to create; if present and marked template:1, destroys it first
  # (rebuild-in-place); if present but NOT a template, refuses to touch it and
  # fails that node, in case the ID was ever repurposed for a real VM. `qm
  # destroy` itself refuses when linked clones exist, which — since it runs
  # inside the same `&&` chain — naturally fails just that node rather than
  # silently orphaning the clone.
  deploy_blocks = [for t in var.targets : <<-EOT
    echo "=== Deploying to ${t.pve_node} (${t.pve_node}.${var.lan_domain}), vmid ${t.vmid} ==="
    if scp ${local.ssh_opts} ${local.local_image} root@${t.pve_node}.${var.lan_domain}:/var/lib/vz/template/iso/${local.image_file} && \
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
         qm create ${t.vmid} --name ${var.template_name} --memory 2048 --net0 virtio,bridge=${var.bridge} --scsihw virtio-scsi-pci --machine q35 &&
         qm set ${t.vmid} --virtio0 ${var.storage_pool}:0,import-from=/var/lib/vz/template/iso/${local.image_file} &&
         qm set ${t.vmid} --ide2 ${var.storage_pool}:cloudinit &&
         qm set ${t.vmid} --boot order=virtio0 &&
         qm set ${t.vmid} --serial0 socket --vga serial0 &&
         qm set ${t.vmid} --agent enabled=1 &&
         qm set ${t.vmid} --bios ${var.bios} --efidisk0 ${var.storage_pool}:1,efitype=4m,pre-enrolled-keys=0 &&
         qm template ${t.vmid}
       '; then
      echo "=== ${t.pve_node}: OK ==="
    else
      echo "=== ${t.pve_node}: FAILED ==="
      FAILED_NODES="$FAILED_NODES ${t.pve_node}"
    fi
  EOT
  ]
  deploy_script = join("\n", local.deploy_blocks)
}

build {
  sources = ["source.null.ubuntu_template"]

  # 1. Download the official cloud image locally (on the machine running Packer —
  #    deliberately not on the PVE node, matching the advice to keep libguestfs off PVE hosts).
  provisioner "shell-local" {
    inline = [
      "mkdir -p ${var.local_staging_dir}",
      "wget -q -O ${local.local_image} ${local.image_url}",
    ]
  }

  # 2. Customize the image offline, before Proxmox ever sees it: install + explicitly
  #    enable qemu-guest-agent (the actual gap we found earlier), plus machine-id hygiene.
  provisioner "shell-local" {
    inline = [<<-EOT
      virt-customize -a ${local.local_image} \
        --network \
        --install qemu-guest-agent \
        --run-command 'systemctl enable qemu-guest-agent.service' \
        --run-command 'truncate -s0 /etc/machine-id'
    EOT
    ]
  }

  # 3. Upload the now-customized image to each target node's storage, create the
  #    VM shell, import the disk, configure cloud-init + firmware + agent channel,
  #    and convert to template. Runs once per node in `var.targets`; one node's
  #    failure doesn't block the others (see local.deploy_script).
  provisioner "shell-local" {
    inline = [<<-EOT
      FAILED_NODES=""
      ${local.deploy_script}
      if [ -n "$FAILED_NODES" ]; then
        echo "Deployment failed for:$FAILED_NODES"
        exit 1
      fi
    EOT
    ]
  }
}

