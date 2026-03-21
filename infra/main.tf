terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Service   = var.service_name
      User      = var.user
      ManagedBy = "terraform"
    }
  }
}

# =============================================================================
# Modules
# =============================================================================

module "rds" {
  source = "./modules/rds"

  service_name      = var.service_name
  subnet_ids        = local.private_subnet_ids
  security_group_id = aws_security_group.rds.id
  instance_class    = var.db_instance_class
  db_name           = var.db_name
  db_password       = random_password.db_password.result
  multi_az          = var.db_multi_az
}

module "langfuse" {
  source = "./modules/langfuse"

  service_name             = var.service_name
  aws_region               = var.aws_region
  vpc_id                   = local.vpc_id
  public_subnet_ids        = local.public_subnet_ids
  private_subnet_ids       = local.private_subnet_ids
  web_security_group_id    = aws_security_group.web.id
  worker_security_group_id = aws_security_group.worker.id
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn
  task_role_id             = aws_iam_role.ecs_task.id

  web_image            = var.langfuse_web_image
  worker_image         = var.langfuse_worker_image
  web_cpu              = var.web_cpu
  web_memory           = var.web_memory
  worker_cpu           = var.worker_cpu
  worker_memory        = var.worker_memory
  worker_desired_count = var.worker_desired_count
  cache_node_type      = var.cache_node_type

  nextauth_url = var.nextauth_url

  database_url_arn        = aws_secretsmanager_secret.database_url.arn
  nextauth_secret_arn     = aws_secretsmanager_secret.nextauth_secret.arn
  salt_arn                = aws_secretsmanager_secret.salt.arn
  encryption_key_arn      = aws_secretsmanager_secret.encryption_key.arn
  clickhouse_password_arn = aws_secretsmanager_secret.clickhouse_password.arn

  # ALB configuration
  enable_alb                 = var.enable_alb
  certificate_arn            = var.certificate_arn
  allowed_cidrs              = var.allowed_cidrs
  allowed_security_group_ids = var.allowed_security_group_ids

  # Custom domain (optional)
  custom_domain   = var.custom_domain
  route53_zone_id = var.route53_zone_id
}

module "clickhouse" {
  source = "./modules/clickhouse"

  service_name            = var.service_name
  vpc_id                  = local.vpc_id
  private_subnet_ids      = local.private_subnet_ids
  security_group_id       = aws_security_group.clickhouse.id
  efs_security_group_id   = aws_security_group.efs.id
  ecs_cluster_id          = module.langfuse.cluster_id
  execution_role_arn      = aws_iam_role.ecs_task_execution.arn
  task_role_arn           = aws_iam_role.ecs_task.arn
  task_role_id            = aws_iam_role.ecs_task.id
  clickhouse_password_arn = aws_secretsmanager_secret.clickhouse_password.arn
  aws_region              = var.aws_region
  image                   = var.clickhouse_image
  cpu                     = var.clickhouse_cpu
  memory                  = var.clickhouse_memory
}
