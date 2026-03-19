# CloudWatch Log Group for Web
resource "aws_cloudwatch_log_group" "web" {
  name              = "/ecs/${var.service_name}/web"
  retention_in_days = 30
}

# Langfuse Web Task Definition
resource "aws_ecs_task_definition" "web" {
  family                   = "${var.service_name}-web"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.web_cpu
  memory                   = var.web_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  # ARM64 architecture for cost efficiency (Graviton)
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name  = "langfuse-web"
      image = var.web_image

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
    Name = "${var.service_name}-web"
  }
}

# Langfuse Web ECS Service
resource "aws_ecs_service" "web" {
  name            = "${var.service_name}-web"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [var.web_security_group_id]
    assign_public_ip = true
  }

  tags = {
    Name = "${var.service_name}-web"
  }
}
