# Plain A record - single host, no Failover/Weighted Round Robin app
# needed (that mechanism exists to solve the multi-A-record fast-flux
# problem, which doesn't arise with exactly one target).
resource "technitium_record" "secrets" {
  domain     = var.secrets_domain
  type       = "A"
  ttl        = var.record_ttl
  ip_address = var.secrets_ipaddr
}
