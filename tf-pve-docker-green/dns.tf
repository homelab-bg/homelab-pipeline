# docker1.lan.homelab.green - plain A record, the host's own identity (SSH,
# inventory). No Failover/Weighted Round Robin app needed anywhere in this
# module: that mechanism exists to solve the multi-A-record fast-flux
# problem, which doesn't arise with exactly one target - a single host is
# the playground tier's whole point, not a gap to route around.
resource "technitium_record" "docker" {
  domain     = var.docker_domain
  type       = "A"
  ttl        = var.dns_record_ttl
  ip_address = var.vm.ipaddr
}

# traefik.lan.homelab.green - direct A record, not a CNAME to docker1.
# Dynamic per-app CNAMEs (dnsweaver, per-container, pointing at this name)
# should resolve in one hop, not chain through docker1 as well.
resource "technitium_record" "traefik" {
  domain     = var.traefik_domain
  type       = "A"
  ttl        = var.dns_record_ttl
  ip_address = var.vm.ipaddr
}

# portainer.lan.homelab.green - CNAME onto traefik, not docker1: reflects
# the actual request path (client -> Traefik -> Portainer container) rather
# than the bare host address.
resource "technitium_record" "portainer" {
  domain = var.portainer_domain
  type   = "CNAME"
  ttl    = var.dns_record_ttl
  cname  = var.traefik_domain
}
