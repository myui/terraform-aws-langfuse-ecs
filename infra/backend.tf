# =============================================================================
# Terraform Backend Configuration (S3 + State Locking)
# =============================================================================
# Stores Terraform state in S3 with native state locking (no DynamoDB needed).
# Requires Terraform >= 1.10 and AWS provider >= 5.0.
#
# Setup:
#   1. Create S3 bucket manually or using bootstrap/main.tf
#   2. Uncomment the backend block below
#   3. Run: terraform init -migrate-state
#
# Reference: https://zenn.dev/terraform_jp/articles/terraform-s3-state-lock
# =============================================================================

# Uncomment after creating the S3 bucket:
#
terraform {
  backend "s3" {
    bucket       = "langfuse-infra-tf-state"
    key          = "langfuse/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true  # Native S3 state locking (Terraform >= 1.10)
    encrypt      = true
  }
}
