talos_version      = "v1.13.9"
talos_schematic_id = "ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515"

template_name = "talos-1.13"
bios          = "ovmf"

# Same <9 prefix><version digits><node index> pattern as
# noble.pkrvars.hcl/resolute.pkrvars.hcl (924041/926041 = 9 + 2404/2604 + 1) -
# now major.minor only, zero-padded to 2 digits each (1.13 -> "01"+"13" =
# "0113"), matching Ubuntu's identity-only naming rather than encoding the
# exact patch version here. Previously this vmid baked in the full patch
# digit (911391 = 9+1139+1), but that meant every patch bump needed a new
# vmid - and had no headroom past a single digit (v1.13.10 wouldn't fit).
# The vmid is the identity of a slot tf-pve-* modules clone from; the actual
# provenance (exact talos_version + schematic ID + build date) lives in the
# template's Proxmox description/tags instead, stamped at build time by
# talos-build.pkr.hcl - open it in the Proxmox UI to see exactly what's
# deployed, no need to cross-reference this file.
targets = [
  { pve_node = "pve1", vmid = 901131 },
  { pve_node = "pve2", vmid = 901132 },
  { pve_node = "pve3", vmid = 901133 },
]
