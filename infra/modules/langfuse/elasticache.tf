# Security Group for Redis
resource "aws_security_group" "redis" {
  name        = "${var.service_name}-redis"
  description = "Security group for ElastiCache Redis"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis from Web/Worker"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.web_security_group_id, var.worker_security_group_id]
  }

  tags = {
    Name = "${var.service_name}-redis"
  }
}

# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.service_name}-redis-subnet"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.service_name}-redis-subnet"
  }
}

# ElastiCache Redis Cluster
resource "aws_elasticache_cluster" "main" {
  cluster_id           = "${var.service_name}-redis"
  engine               = "redis"
  engine_version       = "7.1"
  node_type            = var.cache_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  tags = {
    Name = "${var.service_name}-redis"
  }
}
