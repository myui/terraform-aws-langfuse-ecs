output "service_name" {
  description = "ClickHouse ECS service name"
  value       = aws_ecs_service.main.name
}

output "dns_name" {
  description = "ClickHouse DNS name"
  value       = "${aws_service_discovery_service.main.name}.${aws_service_discovery_private_dns_namespace.main.name}"
}

output "http_url" {
  description = "ClickHouse HTTP URL"
  value       = "http://${aws_service_discovery_service.main.name}.${aws_service_discovery_private_dns_namespace.main.name}:8123"
}

output "migration_url" {
  description = "ClickHouse migration URL"
  value       = "clickhouse://${aws_service_discovery_service.main.name}.${aws_service_discovery_private_dns_namespace.main.name}:9000"
}

output "efs_file_system_arn" {
  description = "EFS file system ARN"
  value       = aws_efs_file_system.main.arn
}

output "efs_access_point_arn" {
  description = "EFS access point ARN"
  value       = aws_efs_access_point.main.arn
}
