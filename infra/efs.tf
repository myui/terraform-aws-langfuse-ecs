# EFS File System for ClickHouse data persistence
resource "aws_efs_file_system" "clickhouse" {
  creation_token = "${var.service_name}-clickhouse"
  encrypted      = true

  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = {
    Name = "${var.service_name}-clickhouse"
  }
}

# EFS Mount Targets (one per private subnet)
resource "aws_efs_mount_target" "clickhouse" {
  for_each = toset(var.private_subnet_ids)

  file_system_id  = aws_efs_file_system.clickhouse.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

# EFS Access Point for ClickHouse
resource "aws_efs_access_point" "clickhouse" {
  file_system_id = aws_efs_file_system.clickhouse.id

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
