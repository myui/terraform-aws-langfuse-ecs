# =============================================================================
# Local Values
# =============================================================================

locals {
  # VPC configuration
  # Use provided VPC/subnets or created ones
  vpc_id             = var.vpc_id != null ? var.vpc_id : aws_vpc.main[0].id
  public_subnet_ids  = var.public_subnet_ids != null ? var.public_subnet_ids : aws_subnet.public[*].id
  private_subnet_ids = var.private_subnet_ids != null ? var.private_subnet_ids : aws_subnet.private[*].id

  # Determine if we need to create VPC resources
  create_vpc = var.vpc_id == null

  # Availability zones (use first 2 AZs in the region)
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}
