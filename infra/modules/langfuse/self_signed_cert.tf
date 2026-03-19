# =============================================================================
# Self-Signed Certificate for ALB HTTPS
# =============================================================================
# Creates a self-signed certificate when:
#   - enable_alb = true
#   - certificate_arn is not provided
#
# Note: Browsers will show a security warning for self-signed certificates.
# For production, use ACM with a custom domain.
# =============================================================================

# CA Private Key
resource "tls_private_key" "ca" {
  count = var.enable_alb && var.certificate_arn == "" ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

# CA Certificate (self-signed)
resource "tls_self_signed_cert" "ca" {
  count = var.enable_alb && var.certificate_arn == "" ? 1 : 0

  private_key_pem       = tls_private_key.ca[0].private_key_pem
  validity_period_hours = 8760 # 1 year

  subject {
    common_name  = "${var.service_name} CA"
    organization = var.service_name
    country      = "JP"
  }

  is_ca_certificate = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

# Server Private Key
resource "tls_private_key" "server" {
  count = var.enable_alb && var.certificate_arn == "" ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 2048
}

# Server Certificate Request
resource "tls_cert_request" "server" {
  count = var.enable_alb && var.certificate_arn == "" ? 1 : 0

  private_key_pem = tls_private_key.server[0].private_key_pem

  subject {
    common_name  = "${var.service_name}.local"
    organization = var.service_name
    country      = "JP"
  }

  # Include ALB DNS name pattern and custom domain if provided
  dns_names = compact([
    "${var.service_name}.local",
    "*.elb.amazonaws.com",
    "*.${var.aws_region}.elb.amazonaws.com",
    var.custom_domain,
  ])
}

# Server Certificate (signed by CA)
resource "tls_locally_signed_cert" "server" {
  count = var.enable_alb && var.certificate_arn == "" ? 1 : 0

  cert_request_pem   = tls_cert_request.server[0].cert_request_pem
  ca_private_key_pem = tls_private_key.ca[0].private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca[0].cert_pem

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# Import to ACM
resource "aws_acm_certificate" "self_signed" {
  count = var.enable_alb && var.certificate_arn == "" ? 1 : 0

  private_key       = tls_private_key.server[0].private_key_pem
  certificate_body  = tls_locally_signed_cert.server[0].cert_pem
  certificate_chain = tls_self_signed_cert.ca[0].cert_pem

  tags = {
    Name = "${var.service_name}-self-signed"
  }

  lifecycle {
    create_before_destroy = true
  }
}
