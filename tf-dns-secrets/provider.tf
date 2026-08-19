provider "technitium" {
  url   = var.technitium_url
  token = var.technitium_token

  skip_certificate_verification = false
}
