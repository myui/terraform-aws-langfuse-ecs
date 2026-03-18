variable "service_name" {
  description = "Service name for resource naming"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for ClickHouse"
  type        = string
}

variable "efs_security_group_id" {
  description = "Security group ID for EFS"
  type        = string
}

variable "ecs_cluster_id" {
  description = "ECS cluster ID"
  type        = string
}

variable "execution_role_arn" {
  description = "ECS task execution role ARN"
  type        = string
}

variable "task_role_arn" {
  description = "ECS task role ARN"
  type        = string
}

variable "task_role_id" {
  description = "ECS task role ID (for IAM policy attachment)"
  type        = string
}

variable "clickhouse_password_arn" {
  description = "ClickHouse password secret ARN"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "image" {
  description = "ClickHouse container image"
  type        = string
  default     = "clickhouse/clickhouse-server:24"
}

variable "cpu" {
  description = "Task CPU"
  type        = number
  default     = 2048
}

variable "memory" {
  description = "Task memory"
  type        = number
  default     = 4096
}

variable "dns_namespace" {
  description = "DNS namespace for service discovery"
  type        = string
  default     = "langfuse.local"
}
