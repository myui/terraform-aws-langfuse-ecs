variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "service_name" {
  description = "Resource naming prefix and service tag"
  type        = string
  default     = "langfuse"
}

variable "user" {
  description = "User tag for resource identification"
  type        = string
}

# VPC Configuration
# If vpc_id is null, a new VPC will be created automatically
variable "vpc_id" {
  description = "Existing VPC ID. If null, a new VPC will be created."
  type        = string
  default     = null
}

variable "public_subnet_ids" {
  description = "Public Subnet IDs for Langfuse Web. Required if vpc_id is provided."
  type        = list(string)
  default     = null
}

variable "private_subnet_ids" {
  description = "Private Subnet IDs for Worker/ClickHouse/RDS/ElastiCache. Required if vpc_id is provided."
  type        = list(string)
  default     = null
}

variable "vpc_cidr" {
  description = "CIDR block for new VPC (used only when vpc_id is null)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "exclude_az_ids" {
  description = "AZ IDs to exclude (e.g., use1-az3 doesn't support ARM64 Fargate in us-east-1)"
  type        = list(string)
  default     = ["use1-az3"]
}

variable "allowed_cidrs" {
  description = "Allowed CIDR list for external access"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security group IDs allowed to access ALB (for internal AWS services tracing)"
  type        = list(string)
  default     = []
}

# RDS
variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "langfuse"
}

variable "db_multi_az" {
  description = "Enable Multi-AZ for RDS"
  type        = bool
  default     = false
}

# ElastiCache
variable "cache_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t4g.micro"
}

# ECS - Web
variable "web_cpu" {
  description = "Web task CPU (1024 = 1 vCPU)"
  type        = number
  default     = 1024
}

variable "web_memory" {
  description = "Web task memory in MB"
  type        = number
  default     = 2048
}

# ECS - Worker
variable "worker_desired_count" {
  description = "Langfuse Worker task count"
  type        = number
  default     = 1
}

variable "worker_cpu" {
  description = "Worker task CPU (1024 = 1 vCPU)"
  type        = number
  default     = 1024
}

variable "worker_memory" {
  description = "Worker task memory in MB"
  type        = number
  default     = 2048
}

# ECS - ClickHouse
variable "clickhouse_cpu" {
  description = "ClickHouse task CPU (1024 = 1 vCPU)"
  type        = number
  default     = 2048
}

variable "clickhouse_memory" {
  description = "ClickHouse task memory in MB"
  type        = number
  default     = 4096
}

# Container Images (ECR)
# ECR repositories must be created beforehand and images pushed before deployment.
# See scripts/push-images.sh for helper script.
variable "langfuse_web_image" {
  description = "Langfuse Web container image (ECR URL with tag)"
  type        = string
  # Example: "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/langfuse-web:3"
}

variable "langfuse_worker_image" {
  description = "Langfuse Worker container image (ECR URL with tag)"
  type        = string
  # Example: "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/langfuse-worker:3"
}

variable "clickhouse_image" {
  description = "ClickHouse container image (ECR URL with tag)"
  type        = string
  # Example: "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/clickhouse:24"
}

variable "nextauth_url" {
  description = "Langfuse Web public URL (e.g., https://langfuse.example.com)"
  type        = string
  default     = ""
}

# ALB Configuration
variable "enable_alb" {
  description = "Enable ALB (recommended for production)"
  type        = bool
  default     = true
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS. If empty, a self-signed certificate is used."
  type        = string
  default     = ""
}

# Custom Domain Configuration (optional)
variable "custom_domain" {
  description = "Custom domain for Langfuse (e.g., langfuse.example.com). Requires Route53 hosted zone."
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for custom domain. Required when custom_domain is set."
  type        = string
  default     = ""
}
