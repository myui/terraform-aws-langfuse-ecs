# AWS Configuration
aws_region   = "us-east-1"
service_name = "langfuse"

# Resource Tags (for easy identification)
user = "your-name"  # e.g., "john", "team-ml"

# Container Images (ECR URLs - must be pushed beforehand)
# See README for ECR setup instructions
langfuse_web_image    = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/langfuse-dev/web:3"
langfuse_worker_image = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/langfuse-dev/worker:3"
clickhouse_image      = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/langfuse-dev/clickhouse:24"

# Network Configuration
# Option A: Auto-create VPC (comment out vpc_id and subnet_ids)
vpc_cidr = "10.0.0.0/16"

# Option B: Use existing VPC (uncomment and set values)
# vpc_id             = "vpc-xxxxxxxxxxxxxxxxx"
# public_subnet_ids  = ["subnet-xxxxxxxxxxxxxxxxx"]
# private_subnet_ids = ["subnet-xxxxxxxxxxxxxxxxx", "subnet-yyyyyyyyyyyyyyyyy"]

# Access Control
allowed_cidrs = ["203.0.113.0/24"]  # Replace with your IP range

# RDS Configuration
db_instance_class = "db.t4g.micro"
db_name           = "langfuse"
db_multi_az       = false

# ElastiCache Configuration
cache_node_type = "cache.t4g.micro"

# ECS - Web Configuration
web_cpu    = 1024  # 1 vCPU
web_memory = 2048  # 2 GB

# ECS - Worker Configuration
worker_desired_count = 1
worker_cpu           = 1024  # 1 vCPU
worker_memory        = 2048  # 2 GB

# ECS - ClickHouse Configuration
clickhouse_cpu    = 2048  # 2 vCPU
clickhouse_memory = 4096  # 4 GB

# Langfuse Configuration
# NEXTAUTH_URL is required for authentication to work properly.
# After first deployment, get the Public IP and update this value, then run terraform apply again.
# nextauth_url = "http://<your-public-ip>:3000"
