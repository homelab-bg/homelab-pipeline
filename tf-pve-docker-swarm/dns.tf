# Traefik/Portainer Failover APP records (Technitium's "Failover" DNS app,
# classPath Failover.Address) - replaces the earlier plain round-robin A
# records. Multiple A records for one hostname tripped a Chrome Safe Browsing
# "fast flux" false positive; the Failover app health-checks every candidate
# and returns exactly one A record per query, switching automatically between
# primary/secondary based on real HTTPS health checks against the record's
# own hostname. Requires an unsigned zone - Technitium rejects APP records on
# DNSSEC-signed primary zones, which is why these live under lan.homelab.blue
# rather than the clustered (DNSSEC-signed, can't be unsigned) lan.bauer.com.au.
# Both primary/secondary tolerate multiple addresses - the app round-robins
# across whichever are healthy within a tier while still returning a single
# record - so a "3rd target" just means adding it to the secondary list here.
locals {
  traefik_secondary_ips = [
    for k, v in local.instances : v.ipaddr if k != var.traefik_failover_primary
  ]
  portainer_secondary_ips = [
    for k, v in local.instances : v.ipaddr if k != var.portainer_failover_primary
  ]
}

resource "technitium_record" "traefik" {
  domain     = var.traefik_domain
  type       = "APP"
  ttl        = var.dns_record_ttl
  app_name   = "Failover"
  class_path = "Failover.Address"
  record_data = jsonencode({
    primary        = [local.instances[var.traefik_failover_primary].ipaddr]
    secondary      = local.traefik_secondary_ips
    serverDown     = []
    healthCheck    = "https"
    healthCheckUrl = null
    allowTxtStatus = true
  })
}

resource "technitium_record" "portainer" {
  domain     = var.portainer_domain
  type       = "APP"
  ttl        = var.dns_record_ttl
  app_name   = "Failover"
  class_path = "Failover.Address"
  record_data = jsonencode({
    primary        = [local.instances[var.portainer_failover_primary].ipaddr]
    secondary      = local.portainer_secondary_ips
    serverDown     = []
    healthCheck    = "https"
    healthCheckUrl = null
    allowTxtStatus = true
  })
}
