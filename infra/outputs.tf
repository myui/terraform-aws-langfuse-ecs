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

output "langfuse_worker_service_name" {
  description = "ECS service name for Langfuse Worker"
  value       = module.langfuse.worker_service_name
}

# =============================================================================
# GitHub Actions 用出力（GHA Variables に設定する値）
# =============================================================================

output "ecr_web_repository_url" {
  description = "ECR Web リポジトリ URL（GitHub Actions Variables: ECR_WEB_REPOSITORY_URL）"
  value       = aws_ecr_repository.web.repository_url
}

output "ecr_worker_repository_url" {
  description = "ECR Worker リポジトリ URL（GitHub Actions Variables: ECR_WORKER_REPOSITORY_URL）"
  value       = aws_ecr_repository.worker.repository_url
}

output "ecr_clickhouse_repository_url" {
  description = "ECR ClickHouse リポジトリ URL（GitHub Actions Variables: ECR_CLICKHOUSE_REPOSITORY_URL）"
  value       = aws_ecr_repository.clickhouse.repository_url
}

output "github_actions_role_arn" {
  description = "GitHub Actions OIDC 用 IAM ロール ARN（GitHub Actions Variables: AWS_ROLE_ARN）"
  value       = aws_iam_role.github_actions.arn
}
