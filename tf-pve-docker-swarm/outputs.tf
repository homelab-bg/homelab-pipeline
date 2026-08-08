output "instances" {
  description = "Name, IP, and node for every provisioned VM - feed into an Ansible inventory"
  value = {
    for name, vm in local.instances : name => {
      ip    = vm.ipaddr
      node  = vm.target_node
      vm_id = vm.vmid
    }
  }
}

