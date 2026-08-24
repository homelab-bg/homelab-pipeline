output "ipaddr" {
  value       = "172.16.0.17"
  description = "Static IP the NetBox LXC was configured with"
}

output "domain" {
  value       = technitium_record.netbox.domain
  description = "FQDN for the NetBox LXC"
}
