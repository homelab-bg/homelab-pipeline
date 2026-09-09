locals {
  ipaddr = split("/", netbox_available_ip_address.mcp_agents.ip_address)[0]

  mcp_service_domains = {
    docker_mcp_agents = var.docker_mcp_agents_domain
    ha_mcp            = var.ha_mcp_domain
    unifi_network_mcp = var.unifi_network_mcp_domain
    unifi_protect_mcp = var.unifi_protect_mcp_domain
    unifi_access_mcp  = var.unifi_access_mcp_domain
    truenas_mcp       = var.truenas_mcp_domain
  }
}

# docker-mcp-agents.lan.homelab.green (the host's own identity) plus one A
# record per MCP service hostname - all point at the same VM, since the
# docker-mcp-agents repo's own Caddy reverse-proxies each hostname to the
# right container. Unlike tf-pve-docker-green's traefik/portainer split, no
# CNAME chain is needed here: none of these hostnames are secondary to
# another, each is its own direct entry point through Caddy.
resource "technitium_record" "mcp" {
  for_each = local.mcp_service_domains

  domain     = each.value
  type       = "A"
  ttl        = var.dns_record_ttl
  ip_address = local.ipaddr
}
