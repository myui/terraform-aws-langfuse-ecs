# CloudWatch Log Group for ClickHouse
resource "aws_cloudwatch_log_group" "main" {
  name              = "/ecs/${var.service_name}/clickhouse"
  retention_in_days = 30
}

# ClickHouse Task Definition
resource "aws_ecs_task_definition" "main" {
  family                   = "${var.service_name}-clickhouse"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  volume {
    name = "clickhouse-data"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.main.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.main.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name  = "clickhouse"
      image = var.image

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
          valueFrom = var.clickhouse_password_arn
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
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "clickhouse"
        }
      }

      essential = true
    }
  ])

  tags = {
    Name = "${var.service_name}-clickhouse"
  }
}

# ClickHouse ECS Service
resource "aws_ecs_service" "main" {
  name            = "${var.service_name}-clickhouse"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  platform_version = "1.4.0"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.security_group_id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.main.arn
  }

  depends_on = [
    aws_efs_mount_target.main
  ]

  tags = {
    Name = "${var.service_name}-clickhouse"
  }
}
