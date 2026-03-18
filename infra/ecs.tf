# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = var.project_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = var.project_name
  }
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "web" {
  name              = "/ecs/${var.project_name}/web"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/ecs/${var.project_name}/worker"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "clickhouse" {
  name              = "/ecs/${var.project_name}/clickhouse"
  retention_in_days = 30
}

# Local values for common environment variables
locals {
  clickhouse_url           = "http://clickhouse.langfuse.local:8123"
  clickhouse_migration_url = "clickhouse://clickhouse.langfuse.local:9000"
  redis_connection_string  = "redis://${aws_elasticache_cluster.main.cache_nodes[0].address}:6379"

  common_environment = [
    {
      name  = "CLICKHOUSE_URL"
      value = local.clickhouse_url
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
      valueFrom = aws_secretsmanager_secret.database_url.arn
    },
    {
      name      = "DIRECT_URL"
      valueFrom = aws_secretsmanager_secret.database_url.arn
    },
    {
      name      = "NEXTAUTH_SECRET"
      valueFrom = aws_secretsmanager_secret.nextauth_secret.arn
    },
    {
      name      = "SALT"
      valueFrom = aws_secretsmanager_secret.salt.arn
    },
    {
      name      = "ENCRYPTION_KEY"
      valueFrom = aws_secretsmanager_secret.encryption_key.arn
    },
    {
      name      = "CLICKHOUSE_PASSWORD"
      valueFrom = aws_secretsmanager_secret.clickhouse_password.arn
    }
  ]
}

# ==================== Langfuse Web ====================

resource "aws_ecs_task_definition" "web" {
  family                   = "${var.project_name}-web"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.web_cpu
  memory                   = var.web_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name  = "langfuse-web"
      image = var.langfuse_web_image

      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]

      environment = concat(local.common_environment, [
        {
          name  = "NEXTAUTH_URL"
          value = var.nextauth_url != "" ? var.nextauth_url : "http://localhost:3000"
        }
      ])

      secrets = local.common_secrets

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.web.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "web"
        }
      }

      essential = true
    }
  ])

  tags = {
    Name = "${var.project_name}-web"
  }
}

resource "aws_ecs_service" "web" {
  name            = "${var.project_name}-web"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [aws_security_group.web.id]
    assign_public_ip = true
  }

  depends_on = [
    aws_ecs_service.clickhouse,
    aws_db_instance.main,
    aws_elasticache_cluster.main
  ]

  tags = {
    Name = "${var.project_name}-web"
  }
}

# ==================== Langfuse Worker ====================

resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.project_name}-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.worker_cpu
  memory                   = var.worker_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name  = "langfuse-worker"
      image = var.langfuse_worker_image

      portMappings = [
        {
          containerPort = 3030
          hostPort      = 3030
          protocol      = "tcp"
        }
      ]

      environment = local.common_environment

      secrets = local.common_secrets

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.worker.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "worker"
        }
      }

      essential = true
    }
  ])

  tags = {
    Name = "${var.project_name}-worker"
  }
}

resource "aws_ecs_service" "worker" {
  name            = "${var.project_name}-worker"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = var.worker_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.worker.id]
    assign_public_ip = false
  }

  depends_on = [
    aws_ecs_service.clickhouse,
    aws_db_instance.main,
    aws_elasticache_cluster.main
  ]

  tags = {
    Name = "${var.project_name}-worker"
  }
}

# ==================== ClickHouse ====================

resource "aws_ecs_task_definition" "clickhouse" {
  family                   = "${var.project_name}-clickhouse"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.clickhouse_cpu
  memory                   = var.clickhouse_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  volume {
    name = "clickhouse-data"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.clickhouse.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.clickhouse.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name  = "clickhouse"
      image = var.clickhouse_image

      portMappings = [
        {
          containerPort = 8123
          hostPort      = 8123
          protocol      = "tcp"
        },
        {
          containerPort = 9000
          hostPort      = 9000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "CLICKHOUSE_USER"
          value = "default"
        }
      ]

      secrets = [
        {
          name      = "CLICKHOUSE_PASSWORD"
          valueFrom = aws_secretsmanager_secret.clickhouse_password.arn
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "clickhouse-data"
          containerPath = "/var/lib/clickhouse"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.clickhouse.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "clickhouse"
        }
      }

      essential = true
    }
  ])

  tags = {
    Name = "${var.project_name}-clickhouse"
  }
}

resource "aws_ecs_service" "clickhouse" {
  name            = "${var.project_name}-clickhouse"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.clickhouse.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  platform_version = "1.4.0"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.clickhouse.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.clickhouse.arn
  }

  depends_on = [
    aws_efs_mount_target.clickhouse
  ]

  tags = {
    Name = "${var.project_name}-clickhouse"
  }
}
