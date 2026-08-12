# docker1.lan.homelab.green - plain A record. No Failover/Weighted Round
# Robin app needed here: that mechanism exists to solve the multi-A-record
# fast-flux problem (see tf-pve-docker-swarm/dns.tf), which doesn't arise
# with exactly one target - a single host is the playground tier's whole
# point, not a gap to route around.
resource "technitium_record" "docker" {
  domain     = var.docker_domain
  type       = "A"
  ttl        = var.dns_record_ttl
  ip_address = var.vm.ipaddr
}

# Service SNIs - CNAMEs onto docker1's own A record rather than separate A
# records, since there's only ever one IP behind them on a single-host
# deployment. Traefik's own dashboard and Portainer each get a dedicated
# hostname; docker1.lan.homelab.green stays the host's own identity (SSH,
# inventory) rather than also being a Traefik vhost.
resource "technitium_record" "portainer" {
  domain = var.portainer_domain
  type   = "CNAME"
  ttl    = var.dns_record_ttl
  cname  = var.docker_domain
}

resource "technitium_record" "traefik" {
  domain = var.traefik_domain
  type   = "CNAME"
  ttl    = var.dns_record_ttl
  cname  = var.docker_domain
}
