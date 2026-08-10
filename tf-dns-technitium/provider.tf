provider "technitium" {
  url   = var.technitium_url
  token = var.technitium_token

  # Real cert now in place (was self-signed, causing a connection-reuse bug
  # where every 2nd+ request on a kept-alive connection failed with an empty
  # response - fixed itself once the real cert was installed, confirmed
  # 2026-08-10).
  skip_certificate_verification = false
}
