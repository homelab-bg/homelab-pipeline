ubuntu_codename = "resolute"
ubuntu_version  = "26.04"

template_name = "ubuntu-server-26.04-lts"
bios          = "ovmf"

targets = [
  { pve_node = "pve1", vmid = 926041 },
  { pve_node = "pve2", vmid = 926042 },
  { pve_node = "pve3", vmid = 926043 },
]
