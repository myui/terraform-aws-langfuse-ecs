# Security Group for Langfuse Web
resource "aws_security_group" "web" {
  name        = "${var.project_name}-web"
  description = "Security group for Langfuse Web"
  vpc_id      = var.vpc_id

  ingress {
    description = "Langfuse Web from allowed CIDRs"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-web"
  }
}

# Security Group for Langfuse Worker
resource "aws_security_group" "worker" {
  name        = "${var.project_name}-worker"
  description = "Security group for Langfuse Worker"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Health check from Web"
    from_port       = 3030
    to_port         = 3030
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-worker"
  }
}

# Security Group for ClickHouse
resource "aws_security_group" "clickhouse" {
  name        = "${var.project_name}-clickhouse"
  description = "Security group for ClickHouse"
  vpc_id      = var.vpc_id

  ingress {
    description     = "ClickHouse HTTP from Web/Worker"
    from_port       = 8123
    to_port         = 8123
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id, aws_security_group.worker.id]
  }

  ingress {
    description     = "ClickHouse TCP from Web/Worker"
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id, aws_security_group.worker.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-clickhouse"
  }
}

# Security Group for RDS
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from Web/Worker"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id, aws_security_group.worker.id]
  }

  tags = {
    Name = "${var.project_name}-rds"
  }
}

# Security Group for Redis
resource "aws_security_group" "redis" {
  name        = "${var.project_name}-redis"
  description = "Security group for ElastiCache Redis"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis from Web/Worker"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id, aws_security_group.worker.id]
  }

  tags = {
    Name = "${var.project_name}-redis"
  }
}

# Security Group for EFS
resource "aws_security_group" "efs" {
  name        = "${var.project_name}-efs"
  description = "Security group for EFS"
  vpc_id      = var.vpc_id

  ingress {
    description     = "NFS from ClickHouse"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.clickhouse.id]
  }

  tags = {
    Name = "${var.project_name}-efs"
  }
}
