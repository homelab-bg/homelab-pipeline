# ipam.lan.bauer.com.au - plain A record, matches tf-pve-docker-green's
# pattern for a host's own identity. Single target, so no
# Failover/Weighted Round Robin app needed here either.
resource "technitium_record" "netbox" {
  domain     = var.netbox_domain
  type       = "A"
  ttl        = var.dns_record_ttl
  ip_address = local.ipaddr
}
