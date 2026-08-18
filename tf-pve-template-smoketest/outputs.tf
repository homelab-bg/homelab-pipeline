output "test_vm_ipv4" {
  value       = proxmox_virtual_environment_vm.test.ipv4_addresses
  description = "IP addresses reported by the QEMU guest agent (populated after boot + agent handshake)"
}

