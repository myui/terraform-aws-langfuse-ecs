# =============================================================================
# VPC Configuration
# =============================================================================
# Creates a new VPC when var.vpc_id is not provided.
# The VPC includes:
#   - 2 Public Subnets (for Langfuse Web with public IP)
#   - 2 Private Subnets (for Worker, ClickHouse, RDS, ElastiCache)
#   - Internet Gateway (for public subnet internet access)
#
# No NAT Gateway - Private subnets use VPC Endpoints for AWS service access.
# See vpc_endpoints.tf for endpoint definitions.
#
# When var.vpc_id is provided, this module is skipped and existing VPC is used.
# =============================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

# =============================================================================
# VPC
# =============================================================================
resource "aws_vpc" "main" {
  count = local.create_vpc ? 1 : 0

  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.service_name}-vpc"
  }
}

# =============================================================================
# Internet Gateway (for public subnets)
# =============================================================================
resource "aws_internet_gateway" "main" {
  count = local.create_vpc ? 1 : 0

  vpc_id = aws_vpc.main[0].id

  tags = {
    Name = "${var.service_name}-igw"
  }
}

# =============================================================================
# Public Subnets
# =============================================================================
resource "aws_subnet" "public" {
  count = local.create_vpc ? length(local.azs) : 0

  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.service_name}-public-${local.azs[count.index]}"
    Type = "public"
  }
}

resource "aws_route_table" "public" {
  count = local.create_vpc ? 1 : 0

  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }

  tags = {
    Name = "${var.service_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = local.create_vpc ? length(local.azs) : 0

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

# =============================================================================
# Private Subnets
# =============================================================================
# No NAT Gateway required - using VPC Endpoints for AWS service access:
#   - ECR API/DKR: Container image pull
#   - CloudWatch Logs: Log delivery
#   - Secrets Manager: Secret retrieval
#   - S3: Gateway endpoint (defined in modules/langfuse/s3.tf)
# =============================================================================
resource "aws_subnet" "private" {
  count = local.create_vpc ? length(local.azs) : 0

  vpc_id            = aws_vpc.main[0].id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + length(local.azs))
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${var.service_name}-private-${local.azs[count.index]}"
    Type = "private"
  }
}

resource "aws_route_table" "private" {
  count = local.create_vpc ? 1 : 0

  vpc_id = aws_vpc.main[0].id

  # No default route to NAT Gateway - all AWS service access via VPC Endpoints

  tags = {
    Name = "${var.service_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count = local.create_vpc ? length(local.azs) : 0

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[0].id
}
