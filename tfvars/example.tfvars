# AWS Configuration
aws_region   = "us-east-1"
service_name = "langfuse"

# Resource Tags (for easy identification)
user = "your-name"  # e.g., "john", "team-ml"

# GitHub Actions OIDC 認証（必須）
github_repo = "moji-inc/ai-eval"

# コンテナイメージ（省略可能）
# 省略した場合は ECR の :latest タグを使用（GitHub Actions が ai-eval/ からビルドしてプッシュ）
# 特定バージョンに固定したい場合のみコメントを外して設定する
# langfuse_web_image    = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/langfuse/web:abc123"
# langfuse_worker_image = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/langfuse/worker:abc123"
# clickhouse_image      = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/langfuse/clickhouse:24"

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

# ECS CPU Architecture for Fargate tasks
# - This repo currently builds/pushes Langfuse images as `linux/amd64` only.
ecs_cpu_architecture = "X86_64"

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
# After first deployment, get the ALB DNS name or Public IP and update this value.
# nextauth_url = "https://langfuse.example.com"  # With ALB + custom domain
# nextauth_url = "http://<your-public-ip>:3000"  # Without ALB

# ALB Configuration (enabled by default)
# - Without certificate_arn: HTTPS with self-signed certificate (browser warning)
# - With certificate_arn: HTTPS with ACM certificate
# enable_alb = true
# certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Custom Domain (optional)
# Requires Route53 hosted zone and ACM certificate for the domain
# custom_domain   = "langfuse.example.com"
# route53_zone_id = "Z1234567890ABC"
