ubuntu_codename = "noble"
ubuntu_version  = "24.04"

template_name = "ubuntu-server-24.04-lts"
bios          = "ovmf"

targets = [
  { pve_node = "pve1", vmid = 924041 },
  { pve_node = "pve2", vmid = 924042 },
  { pve_node = "pve3", vmid = 924043 },
]
