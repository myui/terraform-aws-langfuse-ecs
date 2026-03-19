# VPC outputs
output "vpc_id" {
  description = "VPC ID (created or provided)"
  value       = local.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = local.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = local.private_subnet_ids
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.langfuse.cluster_name
}

output "langfuse_web_service_name" {
  description = "ECS service name for Langfuse Web (use to get public IP)"
  value       = module.langfuse.web_service_name
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = module.rds.endpoint
}

output "redis_endpoint" {
  description = "ElastiCache Redis endpoint"
  value       = module.langfuse.redis_endpoint
}

output "s3_bucket_name" {
  description = "S3 bucket name"
  value       = module.langfuse.s3_bucket_id
}

output "clickhouse_dns" {
  description = "ClickHouse internal DNS name"
  value       = module.clickhouse.dns_name
}

# ALB outputs
output "alb_dns_name" {
  description = "ALB DNS name (when ALB is enabled)"
  value       = module.langfuse.alb_dns_name
}

output "langfuse_url" {
  description = "Langfuse access URL (HTTPS via ALB with ACM or self-signed certificate)"
  value       = var.enable_alb ? "https://${var.custom_domain != "" ? var.custom_domain : module.langfuse.alb_dns_name}" : "http://<public-ip>:3000"
}
