# Random password for RDS
resource "random_password" "db_password" {
  length  = 32
  special = false
}

# Random password for ClickHouse
resource "random_password" "clickhouse_password" {
  length  = 32
  special = false
}

# Random secret for NextAuth
resource "random_password" "nextauth_secret" {
  length  = 64
  special = false
}

# Random salt for API key hashing
resource "random_password" "salt" {
  length  = 32
  special = false
}

# Random encryption key (256-bit hex = 64 hex characters)
resource "random_password" "encryption_key" {
  length  = 64
  special = false
  upper   = false
  numeric = true
  lower   = true
}

# Database URL secret
resource "aws_secretsmanager_secret" "database_url" {
  name = "${var.service_name}/database-url"
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id     = aws_secretsmanager_secret.database_url.id
  secret_string = "postgresql://${aws_db_instance.main.username}:${random_password.db_password.result}@${aws_db_instance.main.endpoint}/${var.db_name}"
}

# NextAuth secret
resource "aws_secretsmanager_secret" "nextauth_secret" {
  name = "${var.service_name}/nextauth-secret"
}

resource "aws_secretsmanager_secret_version" "nextauth_secret" {
  secret_id     = aws_secretsmanager_secret.nextauth_secret.id
  secret_string = random_password.nextauth_secret.result
}

# Salt secret
resource "aws_secretsmanager_secret" "salt" {
  name = "${var.service_name}/salt"
}

resource "aws_secretsmanager_secret_version" "salt" {
  secret_id     = aws_secretsmanager_secret.salt.id
  secret_string = random_password.salt.result
}

# Encryption key secret
resource "aws_secretsmanager_secret" "encryption_key" {
  name = "${var.service_name}/encryption-key"
}

resource "aws_secretsmanager_secret_version" "encryption_key" {
  secret_id     = aws_secretsmanager_secret.encryption_key.id
  secret_string = random_password.encryption_key.result
}

# ClickHouse password secret
resource "aws_secretsmanager_secret" "clickhouse_password" {
  name = "${var.service_name}/clickhouse-password"
}

resource "aws_secretsmanager_secret_version" "clickhouse_password" {
  secret_id     = aws_secretsmanager_secret.clickhouse_password.id
  secret_string = random_password.clickhouse_password.result
}
