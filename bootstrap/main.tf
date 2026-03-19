# =============================================================================
# Bootstrap: Create S3 bucket for Terraform state
# =============================================================================
# Run this once to create the S3 bucket for state management.
#
# Usage:
#   cd bootstrap
#   terraform init
#   terraform apply -var="bucket_name=your-terraform-state-bucket" -var="aws_region=us-east-1"
#
# After creation, update infra/backend.tf with the bucket name.
# =============================================================================

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "bucket_name" {
  description = "S3 bucket name for Terraform state"
  type        = string
}

variable "user" {
  description = "User tag for resource identification"
  type        = string
  default     = ""
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Service   = "terraform-state"
      User      = var.user
      ManagedBy = "terraform"
    }
  }
}

# S3 Bucket for Terraform State
resource "aws_s3_bucket" "terraform_state" {
  bucket = var.bucket_name

  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = var.bucket_name
  }
}

# Enable versioning for state history
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "bucket_name" {
  description = "S3 bucket name for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.terraform_state.arn
}

output "backend_config" {
  description = "Backend configuration to add to infra/backend.tf"
  value       = <<-EOT

    Add the following to infra/backend.tf:

    terraform {
      backend "s3" {
        bucket       = "${aws_s3_bucket.terraform_state.id}"
        key          = "langfuse/terraform.tfstate"
        region       = "${var.aws_region}"
        use_lockfile = true
        encrypt      = true
      }
    }

    Then run: cd ../infra && terraform init -migrate-state
  EOT
}
