# AWS Configuration
aws_region = "ap-northeast-1"

# Resource Tags (for easy identification)
user = "your-name"  # e.g., "john", "team-ml"

# Network Configuration (use your existing VPC)
vpc_id             = "vpc-xxxxxxxxxxxxxxxxx"
public_subnet_ids  = ["subnet-xxxxxxxxxxxxxxxxx"]
private_subnet_ids = ["subnet-xxxxxxxxxxxxxxxxx", "subnet-yyyyyyyyyyyyyyyyy"]

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
# nextauth_url = "http://<your-public-ip>:3000"  # Set after first deployment
