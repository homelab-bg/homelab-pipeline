talos_version      = "v1.13.9"
talos_schematic_id = "ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515"

template_name = "talos-1.13.9"
bios          = "ovmf"

# vmid pattern mirrors noble.pkrvars.hcl/resolute.pkrvars.hcl (924xxx/926xxx
# encode Ubuntu 24.04/26.04) - 913xxx encodes Talos 1.13, deliberately a
# distinct block so it doesn't read as another Ubuntu version.
targets = [
  { pve_node = "pve1", vmid = 913041 },
  { pve_node = "pve2", vmid = 913042 },
  { pve_node = "pve3", vmid = 913043 },
]
