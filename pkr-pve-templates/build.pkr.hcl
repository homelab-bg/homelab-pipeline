locals {
  image_file  = "${var.ubuntu_codename}-server-cloudimg-amd64.img"
  image_url   = "https://cloud-images.ubuntu.com/releases/${var.ubuntu_codename}/release/ubuntu-${var.ubuntu_version}-server-cloudimg-amd64.img"
  local_image = "${var.local_staging_dir}/${local.image_file}"
  ssh_opts    = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes"

  # Provenance stamp for the template's Proxmox description/tags (see
  # talos.pkrvars.hcl's targets comment for why this exists - the
  # codename/version alone don't tell you whether a rebuild actually pulled
  # in a newer upstream image, since cloud-images.ubuntu.com's "release/"
  # path always points at whatever build is currently latest, with no
  # serial in the URL itself). build_date is HCL-computable, but the image's
  # own sha256 can only exist after it's actually downloaded - computed
  # locally in step 1 below and written to description_file, which gets
  # uploaded alongside the image and read back with a remote `cat` rather
  # than threaded through the single-quoted SSH block in deploy_blocks.
  # `sha256=<hash>`, not `sha256:<hash>` - confirmed live that Proxmox
  # percent-encodes a literal `:` in a description (stored/read back as
  # `sha256%3A...`), which silently broke packer-build-templates.yml's
  # (homelab-ci) grep for the marker on its very first real run. `=` passes
  # through unencoded, confirmed the same way.
  build_date        = formatdate("YYYY-MM-DD", timestamp())
  description_file  = "${var.ubuntu_codename}-description.txt"
  local_description = "${var.local_staging_dir}/${local.description_file}"

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
  #
  # --cpu host is explicit (previously unset here, silently defaulting to
  # Proxmox's kvm64 - only discovered as a gap while debugging why the Talos
  # template boot-looped, since Talos hard-requires x86-64-v2 and kvm64
  # doesn't expose it). host is safe cluster-wide because pve1/pve2/pve3 are
  # confirmed identical hardware (Intel i5-8500T, verified live via lscpu on
  # all three) - no live-migration portability risk from pinning to the
  # physical CPU's exact feature set.
  deploy_blocks = [for t in var.targets : <<-EOT
    echo "=== Deploying to ${t.pve_node} (${t.pve_node}.${var.lan_domain}), vmid ${t.vmid} ==="
    if scp ${local.ssh_opts} ${local.local_image} root@${t.pve_node}.${var.lan_domain}:/var/lib/vz/template/iso/${local.image_file} && \
       scp ${local.ssh_opts} ${local.local_description} root@${t.pve_node}.${var.lan_domain}:/var/lib/vz/template/iso/${local.description_file} && \
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
         qm create ${t.vmid} --name ${var.template_name} --memory 2048 --cpu host --net0 virtio,bridge=${var.bridge} --scsihw virtio-scsi-pci --machine q35 &&
         qm set ${t.vmid} --virtio0 ${var.storage_pool}:0,import-from=/var/lib/vz/template/iso/${local.image_file} &&
         qm set ${t.vmid} --ide2 ${var.storage_pool}:cloudinit &&
         qm set ${t.vmid} --boot order=virtio0 &&
         qm set ${t.vmid} --serial0 socket --vga serial0 &&
         qm set ${t.vmid} --agent enabled=1 &&
         qm set ${t.vmid} --bios ${var.bios} --efidisk0 ${var.storage_pool}:1,efitype=4m,pre-enrolled-keys=0 &&
         qm set ${t.vmid} --tags packer,ubuntu,${var.ubuntu_version},built-${local.build_date} &&
         qm set ${t.vmid} --description "$(cat /var/lib/vz/template/iso/${local.description_file})" &&
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
  #    Also computes the provenance description file (see locals.description_file) -
  #    done here, in a plain local shell, specifically to avoid needing to thread a
  #    runtime-computed value through deploy_blocks' single-quoted remote SSH script.
  provisioner "shell-local" {
    inline = [<<-EOT
      mkdir -p ${var.local_staging_dir}
      wget -q -O ${local.local_image} ${local.image_url}
      image_sha=$(sha256sum ${local.local_image} | cut -c1-12)
      printf 'Ubuntu ${var.ubuntu_version} (${var.ubuntu_codename}) cloud image - sha256=%s - built ${local.build_date} via pkr-pve-templates/build.pkr.hcl\n' "$image_sha" > ${local.local_description}
    EOT
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

