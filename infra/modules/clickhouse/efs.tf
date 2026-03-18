# EFS File System for ClickHouse data persistence
resource "aws_efs_file_system" "main" {
  creation_token = "${var.service_name}-clickhouse"
  encrypted      = true

  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = {
    Name = "${var.service_name}-clickhouse"
  }
}

# EFS Mount Targets (one per private subnet)
resource "aws_efs_mount_target" "main" {
  count = length(var.private_subnet_ids)

  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [var.efs_security_group_id]
}

# EFS Access Point for ClickHouse
resource "aws_efs_access_point" "main" {
  file_system_id = aws_efs_file_system.main.id

  posix_user {
    gid = 101 # clickhouse group
    uid = 101 # clickhouse user
  }

  root_directory {
    path = "/clickhouse"
    creation_info {
      owner_gid   = 101
      owner_uid   = 101
      permissions = "755"
    }
  }

  tags = {
    Name = "${var.service_name}-clickhouse"
  }
}

# EFS access policy for ECS Task Role
resource "aws_iam_role_policy" "efs_access" {
  name = "${var.service_name}-efs-access"
  role = var.task_role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = aws_efs_file_system.main.arn
        Condition = {
          StringEquals = {
            "elasticfilesystem:AccessPointArn" = aws_efs_access_point.main.arn
          }
        }
      }
    ]
  })
}
