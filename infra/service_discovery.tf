# Private DNS namespace for service discovery
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "langfuse.local"
  description = "Private DNS namespace for Langfuse services"
  vpc         = var.vpc_id

  tags = {
    Name = "${var.service_name}-namespace"
  }
}

# Service discovery for ClickHouse
resource "aws_service_discovery_service" "clickhouse" {
  name = "clickhouse"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      type = "A"
      ttl  = 10
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = {
    Name = "${var.service_name}-clickhouse"
  }
}
