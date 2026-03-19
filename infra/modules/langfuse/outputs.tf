output "cluster_id" {
  description = "ECS cluster ID"
  value       = aws_ecs_cluster.main.id
}

output "cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "web_service_name" {
  description = "Web ECS service name"
  value       = aws_ecs_service.web.name
}

output "worker_service_name" {
  description = "Worker ECS service name"
  value       = aws_ecs_service.worker.name
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = aws_elasticache_cluster.main.cache_nodes[0].address
}

output "s3_bucket_id" {
  description = "S3 bucket ID"
  value       = aws_s3_bucket.main.id
}

# ALB outputs
output "alb_dns_name" {
  description = "ALB DNS name"
  value       = var.enable_alb ? aws_lb.main[0].dns_name : null
}

output "alb_zone_id" {
  description = "ALB hosted zone ID (for Route53 alias)"
  value       = var.enable_alb ? aws_lb.main[0].zone_id : null
}

output "alb_url" {
  description = "Langfuse Web URL (HTTPS via ALB DNS or custom domain)"
  value       = var.enable_alb ? "https://${var.custom_domain != "" ? var.custom_domain : aws_lb.main[0].dns_name}" : null
}
