variable "talos_version" {
  type        = string
  default     = "v1.13.9"
  description = "Talos release tag - https://github.com/siderolabs/talos/releases. Defaulted (unlike ubuntu_codename/ubuntu_version) because Packer validates every declared variable across the whole directory regardless of -var-file/-only scoping - an unset, default-less variable here would also block running the Ubuntu build. Override via talos.pkrvars.hcl to bump deliberately, same as everywhere else in this project."
}

variable "talos_schematic_id" {
  type        = string
  default     = "ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515"
  description = <<-EOT
    Image Factory schematic ID - pinned, not computed at build time (Packer
    has no live-HTTP-call primitive for this, and this project pins exact
    versions/hashes throughout rather than resolving them dynamically).
    Derived via (bakes in the qemu-guest-agent extension - required for
    Proxmox to detect the VM's IP/send guest commands, confirmed live -
    without it enabling the Proxmox-side QEMU Guest Agent option just
    produces log spam with no functionality):
      curl -s -X POST https://factory.talos.dev/schematics \
        -H "Content-Type: application/json" \
        -d '{"customization":{"systemExtensions":{"officialExtensions":["siderolabs/qemu-guest-agent"]}}}'
    Regenerate if the extension list ever changes.
  EOT
}
