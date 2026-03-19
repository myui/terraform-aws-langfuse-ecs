# CloudWatch Log Group for Worker
resource "aws_cloudwatch_log_group" "worker" {
  name              = "/ecs/${var.service_name}/worker"
  retention_in_days = 30
}

# Langfuse Worker Task Definition
resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.service_name}-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.worker_cpu
  memory                   = var.worker_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  # ARM64 architecture for cost efficiency (Graviton)
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name  = "langfuse-worker"
      image = var.worker_image

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
    Name = "${var.service_name}-worker"
  }
}

# Langfuse Worker ECS Service
resource "aws_ecs_service" "worker" {
  name            = "${var.service_name}-worker"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = var.worker_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.worker_security_group_id]
    assign_public_ip = false
  }

  tags = {
    Name = "${var.service_name}-worker"
  }
}
