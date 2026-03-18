# =============================================================================
# VPC Endpoints
# =============================================================================
# Interface endpoints for ECS Fargate tasks in private subnets to access
# AWS services without NAT Gateway.
#
# Required endpoints:
#   - ECR API: Container image metadata
#   - ECR DKR: Container image pull (Docker Registry)
#   - CloudWatch Logs: Log delivery
#   - Secrets Manager: Secret retrieval
#
# Note: S3 Gateway Endpoint is defined in modules/langfuse/s3.tf
# =============================================================================

# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.service_name}-vpc-endpoints"
  description = "Security group for VPC Endpoints"
  vpc_id      = local.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.create_vpc ? var.vpc_cidr : data.aws_vpc.existing[0].cidr_block]
  }

  tags = {
    Name = "${var.service_name}-vpc-endpoints"
  }
}

# Data source for existing VPC CIDR (when using existing VPC)
data "aws_vpc" "existing" {
  count = local.create_vpc ? 0 : 1
  id    = var.vpc_id
}

# =============================================================================
# ECR API Endpoint
# =============================================================================
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.service_name}-ecr-api-endpoint"
  }
}

# =============================================================================
# ECR DKR Endpoint (Docker Registry)
# =============================================================================
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.service_name}-ecr-dkr-endpoint"
  }
}

# =============================================================================
# CloudWatch Logs Endpoint
# =============================================================================
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.service_name}-logs-endpoint"
  }
}

# =============================================================================
# Secrets Manager Endpoint
# =============================================================================
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.service_name}-secretsmanager-endpoint"
  }
}
