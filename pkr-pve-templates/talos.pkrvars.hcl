talos_version      = "v1.13.9"
talos_schematic_id = "ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515"

template_name = "talos-1.13.9"
bios          = "ovmf"

# Same <9 prefix><version digits><node index> pattern as
# noble.pkrvars.hcl/resolute.pkrvars.hcl (924041/926041 = 9 + 2404/2604 + 1) -
# 1139 encodes Talos 1.13.9 (the exact patch version, not just major.minor,
# since Talos's own version matrix is 1.7, 1.8 ... 1.13 rather than
# Ubuntu-style LTS pairs, so the patch digit is what actually distinguishes
# a rebuild).
targets = [
  { pve_node = "pve1", vmid = 911391 },
  { pve_node = "pve2", vmid = 911392 },
  { pve_node = "pve3", vmid = 911393 },
]
