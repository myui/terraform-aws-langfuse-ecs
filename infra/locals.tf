# =============================================================================
# Local Values
# =============================================================================

locals {
  # VPC configuration
  # Use provided VPC/subnets or created ones
  vpc_id             = var.vpc_id != null ? var.vpc_id : aws_vpc.main[0].id
  public_subnet_ids  = var.public_subnet_ids != null ? var.public_subnet_ids : aws_subnet.public[*].id
  private_subnet_ids = var.private_subnet_ids != null ? var.private_subnet_ids : aws_subnet.private[*].id

  # Determine if we need to create VPC resources
  create_vpc = var.vpc_id == null

  # Availability zones (use first 2 AZs in the region)
  # Exclude AZs that don't support ARM64 Fargate (e.g., use1-az3 in us-east-1).
  # When `ecs_cpu_architecture` is X86_64, no AZs are excluded.
  all_azs                  = data.aws_availability_zones.available.names
  az_ids                   = data.aws_availability_zones.available.zone_ids
  exclude_az_ids_effective = var.ecs_cpu_architecture == "ARM64" ? var.exclude_az_ids : []
  filtered_azs = [
    for i, az in local.all_azs : az
    if !contains(local.exclude_az_ids_effective, local.az_ids[i])
  ]
  azs = slice(local.filtered_azs, 0, min(2, length(local.filtered_azs)))
}

# =============================================================================
# Container Image URL の解決
# =============================================================================
# 変数で明示指定があればそちらを優先、なければ ECR の :latest タグを使用。
# :latest は GitHub Actions が ai-eval/ からビルドしてプッシュする。
locals {
  resolved_web_image        = coalesce(var.langfuse_web_image, "${aws_ecr_repository.web.repository_url}:latest")
  resolved_worker_image     = coalesce(var.langfuse_worker_image, "${aws_ecr_repository.worker.repository_url}:latest")
  resolved_clickhouse_image = coalesce(var.clickhouse_image, "${aws_ecr_repository.clickhouse.repository_url}:latest")
}
