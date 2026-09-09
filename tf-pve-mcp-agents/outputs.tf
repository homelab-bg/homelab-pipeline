output "instance" {
  description = "VM name, IP (requested from NetBox), and node - feed into an Ansible inventory"
  value = {
    ip    = local.ipaddr
    node  = var.vm.node
    vm_id = var.vm.vmid
  }
}
