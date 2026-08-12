output "instance" {
  description = "VM name, IP, and node - feed into an Ansible inventory"
  value = {
    ip    = var.vm.ipaddr
    node  = var.vm.node
    vm_id = var.vm.vmid
  }
}
