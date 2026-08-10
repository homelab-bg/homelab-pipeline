# Traefik/Portainer round-robin A records - one per swarm node, all under the
# same domain name. Valid because both services are published in Swarm's
# default "ingress" mode (confirmed via `docker service inspect` -
# PublishMode: ingress on both), so any node can receive and route traffic
# for either service regardless of which node the container actually runs on.
resource "technitium_record" "traefik" {
  for_each = local.instances

  domain     = var.traefik_domain
  type       = "A"
  ttl        = var.dns_record_ttl
  ip_address = each.value.ipaddr
}

resource "technitium_record" "portainer" {
  for_each = local.instances

  domain     = var.portainer_domain
  type       = "A"
  ttl        = var.dns_record_ttl
  ip_address = each.value.ipaddr
}
