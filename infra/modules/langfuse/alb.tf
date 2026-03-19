# =============================================================================
# Application Load Balancer for Langfuse Web (HTTPS)
# =============================================================================
# Creates ALB with HTTPS listener when enabled.
# Requires:
#   - ACM certificate ARN
#   - Route53 hosted zone (optional, for DNS record creation)
#
# Reference: https://zenn.dev/secula/articles/caff582e044adf
# =============================================================================

# ALB
resource "aws_lb" "main" {
  count = var.enable_alb ? 1 : 0

  name               = "${var.service_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb[0].id]
  subnets            = var.public_subnet_ids

  tags = {
    Name = "${var.service_name}-alb"
  }
}

# ALB Security Group
resource "aws_security_group" "alb" {
  count = var.enable_alb ? 1 : 0

  name        = "${var.service_name}-alb"
  description = "Security group for ALB"
  vpc_id      = var.vpc_id

  # HTTPS from allowed CIDRs (always enabled - uses ACM cert or self-signed)
  ingress {
    description = "HTTPS from allowed CIDRs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  # HTTP from allowed CIDRs
  ingress {
    description = "HTTP from allowed CIDRs"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  # Egress to ECS tasks
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.service_name}-alb"
  }
}

# Target Group
resource "aws_lb_target_group" "web" {
  count = var.enable_alb ? 1 : 0

  name        = "${var.service_name}-web-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/api/public/health"
    protocol            = "HTTP"
    matcher             = "200"
  }

  tags = {
    Name = "${var.service_name}-web-tg"
  }
}

# HTTPS Listener (uses ACM certificate or self-signed certificate)
resource "aws_lb_listener" "https" {
  count = var.enable_alb ? 1 : 0

  load_balancer_arn = aws_lb.main[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn != "" ? var.certificate_arn : aws_acm_certificate.self_signed[0].arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web[0].arn
  }
}

# HTTP Listener - Always redirect to HTTPS
resource "aws_lb_listener" "http" {
  count = var.enable_alb ? 1 : 0

  load_balancer_arn = aws_lb.main[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# Update Web Security Group to allow traffic from ALB
resource "aws_security_group_rule" "web_from_alb" {
  count = var.enable_alb ? 1 : 0

  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb[0].id
  security_group_id        = var.web_security_group_id
  description              = "Allow traffic from ALB"
}

# =============================================================================
# Route53 DNS Record (optional - for custom domain)
# =============================================================================
resource "aws_route53_record" "langfuse" {
  count = var.enable_alb && var.custom_domain != "" && var.route53_zone_id != "" ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.custom_domain
  type    = "A"

  alias {
    name                   = aws_lb.main[0].dns_name
    zone_id                = aws_lb.main[0].zone_id
    evaluate_target_health = true
  }
}
