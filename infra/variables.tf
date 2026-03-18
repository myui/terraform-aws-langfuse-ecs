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

variable "vpc_id" {
  description = "Existing VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public Subnet IDs for Langfuse Web placement"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private Subnet IDs for Worker / ClickHouse / RDS / ElastiCache"
  type        = list(string)
}

variable "allowed_cidrs" {
  description = "Allowed CIDR list for external access"
  type        = list(string)
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

# Langfuse
variable "langfuse_web_image" {
  description = "Langfuse Web container image"
  type        = string
  default     = "langfuse/langfuse:3"
}

variable "langfuse_worker_image" {
  description = "Langfuse Worker container image"
  type        = string
  default     = "langfuse/langfuse-worker:3"
}

variable "clickhouse_image" {
  description = "ClickHouse container image"
  type        = string
  default     = "clickhouse/clickhouse-server:24"
}

variable "nextauth_url" {
  description = "Langfuse Web public URL (e.g., http://<public_ip>:3000)"
  type        = string
  default     = ""
}
