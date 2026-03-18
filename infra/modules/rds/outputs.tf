output "endpoint" {
  description = "RDS endpoint"
  value       = aws_db_instance.main.endpoint
}

output "address" {
  description = "RDS address (without port)"
  value       = aws_db_instance.main.address
}

output "username" {
  description = "RDS username"
  value       = aws_db_instance.main.username
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.main.db_name
}
