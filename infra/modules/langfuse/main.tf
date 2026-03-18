# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = var.service_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = var.service_name
  }
}

# Local values for common environment variables
locals {
  clickhouse_http_url      = "http://clickhouse.${var.clickhouse_dns_namespace}:8123"
  clickhouse_migration_url = "clickhouse://clickhouse.${var.clickhouse_dns_namespace}:9000"
  redis_connection_string  = "redis://${aws_elasticache_cluster.main.cache_nodes[0].address}:6379"

  common_environment = [
    {
      name  = "CLICKHOUSE_URL"
      value = local.clickhouse_http_url
    },
    {
      name  = "CLICKHOUSE_MIGRATION_URL"
      value = local.clickhouse_migration_url
    },
    {
      name  = "CLICKHOUSE_USER"
      value = "default"
    },
    {
      name  = "CLICKHOUSE_CLUSTER_ENABLED"
      value = "false"
    },
    {
      name  = "REDIS_CONNECTION_STRING"
      value = local.redis_connection_string
    },
    {
      name  = "LANGFUSE_S3_EVENT_UPLOAD_BUCKET"
      value = aws_s3_bucket.main.id
    },
    {
      name  = "LANGFUSE_S3_EVENT_UPLOAD_REGION"
      value = var.aws_region
    },
    {
      name  = "HOSTNAME"
      value = "0.0.0.0"
    }
  ]

  common_secrets = [
    {
      name      = "DATABASE_URL"
      valueFrom = var.database_url_arn
    },
    {
      name      = "DIRECT_URL"
      valueFrom = var.database_url_arn
    },
    {
      name      = "NEXTAUTH_SECRET"
      valueFrom = var.nextauth_secret_arn
    },
    {
      name      = "SALT"
      valueFrom = var.salt_arn
    },
    {
      name      = "ENCRYPTION_KEY"
      valueFrom = var.encryption_key_arn
    },
    {
      name      = "CLICKHOUSE_PASSWORD"
      valueFrom = var.clickhouse_password_arn
    }
  ]
}
