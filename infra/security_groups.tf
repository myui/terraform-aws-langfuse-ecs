# =============================================================================
# Security Group for Langfuse Web
# =============================================================================
# Langfuse Web is the main application server that serves the UI and API.
# It runs in a public subnet with a dynamic public IP (no load balancer).
#
# Ingress:
#   - Port 3000 (TCP): Web UI and API access from allowed CIDRs only
#     This is the main entry point for users accessing Langfuse
#
# Egress:
#   - All traffic: Required for external API calls (LLM providers, etc.),
#     and internal communication with RDS, Redis, ClickHouse, S3
# =============================================================================
resource "aws_security_group" "web" {
  name        = "${var.service_name}-web"
  description = "Security group for Langfuse Web"
  vpc_id      = local.vpc_id

  # Ingress: Allow access to Langfuse Web UI/API from specified IP ranges
  # Restrict allowed_cidrs to your office/VPN IPs for security
  ingress {
    description = "Langfuse Web from allowed CIDRs"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  # Egress: Allow all outbound traffic
  # Required for: RDS, Redis, ClickHouse, S3 VPC Endpoint, external LLM APIs
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.service_name}-web"
  }
}

# =============================================================================
# Security Group for Langfuse Worker
# =============================================================================
# Langfuse Worker handles background jobs (trace processing, analytics, etc.).
# It runs in a private subnet with no direct external access.
#
# Ingress:
#   - Port 3030 (TCP): Health check endpoint, accessed only by Web service
#     Web service monitors Worker health for operational visibility
#
# Egress:
#   - All traffic: Required for RDS, Redis, ClickHouse, S3 VPC Endpoint access
# =============================================================================
resource "aws_security_group" "worker" {
  name        = "${var.service_name}-worker"
  description = "Security group for Langfuse Worker"
  vpc_id      = local.vpc_id

  # Ingress: Health check from Web service only
  # Worker does not need external access - it's an internal background processor
  ingress {
    description     = "Health check from Web"
    from_port       = 3030
    to_port         = 3030
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  # Egress: Allow all outbound traffic
  # Required for: RDS, Redis, ClickHouse, S3 VPC Endpoint
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.service_name}-worker"
  }
}

# =============================================================================
# Security Group for ClickHouse
# =============================================================================
# ClickHouse is the analytics database for Langfuse trace data.
# It runs in a private subnet, accessible only by Web and Worker services.
#
# Ingress:
#   - Port 8123 (TCP): HTTP interface for queries (used by Langfuse for reads)
#   - Port 9000 (TCP): Native TCP protocol (used for bulk data ingestion)
#   Both ports restricted to Web and Worker security groups only
#
# Egress:
#   - All traffic: Required for EFS mount (NFS), ECR image pull, CloudWatch logs
# =============================================================================
resource "aws_security_group" "clickhouse" {
  name        = "${var.service_name}-clickhouse"
  description = "Security group for ClickHouse"
  vpc_id      = local.vpc_id

  # Ingress: HTTP interface for analytics queries
  # Used by Web (dashboard queries) and Worker (data aggregation)
  ingress {
    description     = "ClickHouse HTTP from Web/Worker"
    from_port       = 8123
    to_port         = 8123
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id, aws_security_group.worker.id]
  }

  # Ingress: Native TCP protocol for high-performance data operations
  # Used primarily by Worker for bulk trace data ingestion
  ingress {
    description     = "ClickHouse TCP from Web/Worker"
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id, aws_security_group.worker.id]
  }

  # Egress: Allow all outbound traffic
  # Required for: EFS mount (port 2049), ECR image pull, CloudWatch logs
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.service_name}-clickhouse"
  }
}

# =============================================================================
# Security Group for RDS PostgreSQL
# =============================================================================
# RDS PostgreSQL stores Langfuse transactional data (users, projects, configs).
# It runs in a private subnet with no public accessibility.
#
# Ingress:
#   - Port 5432 (TCP): PostgreSQL protocol from Web and Worker only
#     Web: user authentication, project management, configuration
#     Worker: job state management, metadata updates
#
# Egress:
#   - None defined: RDS managed service handles outbound connectivity internally
# =============================================================================
resource "aws_security_group" "rds" {
  name        = "${var.service_name}-rds"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = local.vpc_id

  # Ingress: PostgreSQL access from Langfuse services only
  # No direct external access - all queries go through Web/Worker
  ingress {
    description     = "PostgreSQL from Web/Worker"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id, aws_security_group.worker.id]
  }

  # No egress rules: RDS managed service handles its own outbound connectivity

  tags = {
    Name = "${var.service_name}-rds"
  }
}

# =============================================================================
# Security Group for EFS (Elastic File System)
# =============================================================================
# EFS provides persistent storage for ClickHouse data (/var/lib/clickhouse).
# Mount targets are created in each private subnet for high availability.
#
# Ingress:
#   - Port 2049 (TCP): NFS protocol from ClickHouse containers only
#     ClickHouse uses EFS to persist analytics data across container restarts
#
# Egress:
#   - None defined: EFS mount targets only receive connections, no outbound needed
# =============================================================================
resource "aws_security_group" "efs" {
  name        = "${var.service_name}-efs"
  description = "Security group for EFS"
  vpc_id      = local.vpc_id

  # Ingress: NFS access from ClickHouse only
  # EFS stores ClickHouse data for persistence across Fargate task restarts
  ingress {
    description     = "NFS from ClickHouse"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.clickhouse.id]
  }

  # No egress rules: EFS mount targets are passive - they only receive NFS connections

  tags = {
    Name = "${var.service_name}-efs"
  }
}
