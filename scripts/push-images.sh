#!/bin/bash
# =============================================================================
# Push container images from Docker Hub to ECR
# =============================================================================
# This script pulls images from Docker Hub and pushes them to ECR.
# ECR repositories must be created beforehand.
#
# Prerequisites:
#   - AWS CLI configured with appropriate permissions
#   - Docker installed and running
#   - ECR repositories created
#
# Usage:
#   ./scripts/push-images.sh <aws_account_id> <aws_region> [repository_prefix]
#
# Example:
#   ./scripts/push-images.sh 123456789012 ap-northeast-1 langfuse
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check arguments
if [ $# -lt 2 ]; then
    echo -e "${RED}Usage: $0 <aws_account_id> <aws_region> [repository_prefix]${NC}"
    echo "Example: $0 123456789012 ap-northeast-1 langfuse"
    exit 1
fi

AWS_ACCOUNT_ID="$1"
AWS_REGION="$2"
REPO_PREFIX="${3:-langfuse-dev}"

ECR_BASE="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Source images from Docker Hub
LANGFUSE_WEB_SOURCE="langfuse/langfuse:3"
LANGFUSE_WORKER_SOURCE="langfuse/langfuse-worker:3"
CLICKHOUSE_SOURCE="clickhouse/clickhouse-server:24"

# Target ECR repositories (prefix/name format)
ECR_WEB_URL="${ECR_BASE}/${REPO_PREFIX}/web"
ECR_WORKER_URL="${ECR_BASE}/${REPO_PREFIX}/worker"
ECR_CLICKHOUSE_URL="${ECR_BASE}/${REPO_PREFIX}/clickhouse"

echo -e "${GREEN}=== ECR Image Push Script ===${NC}"
echo "AWS Account: ${AWS_ACCOUNT_ID}"
echo "AWS Region: ${AWS_REGION}"
echo "Repository Prefix: ${REPO_PREFIX}"
echo "Platform: ${PLATFORM}"
echo ""
echo "Target repositories:"
echo "  - ${ECR_WEB_URL}"
echo "  - ${ECR_WORKER_URL}"
echo "  - ${ECR_CLICKHOUSE_URL}"
echo ""

# Login to ECR
echo -e "${YELLOW}Logging in to ECR...${NC}"
aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "${ECR_BASE}"

# Target architecture (ARM64 for Fargate Graviton)
PLATFORM="linux/arm64"

# Function to pull, tag, and push an image
push_image() {
    local source_image="$1"
    local ecr_url="$2"
    local tag="$3"
    local name="$4"

    echo ""
    echo -e "${YELLOW}Processing ${name}...${NC}"

    echo "  Pulling ${source_image} for ${PLATFORM}..."
    docker pull --platform "${PLATFORM}" "${source_image}"

    echo "  Tagging as ${ecr_url}:${tag}..."
    docker tag "${source_image}" "${ecr_url}:${tag}"

    echo "  Pushing to ECR..."
    docker push "${ecr_url}:${tag}"

    echo -e "  ${GREEN}Done!${NC}"
}

# Push all images
push_image "${LANGFUSE_WEB_SOURCE}" "${ECR_WEB_URL}" "3" "Langfuse Web"
push_image "${LANGFUSE_WORKER_SOURCE}" "${ECR_WORKER_URL}" "3" "Langfuse Worker"
push_image "${CLICKHOUSE_SOURCE}" "${ECR_CLICKHOUSE_URL}" "24" "ClickHouse"

echo ""
echo -e "${GREEN}=== All images pushed successfully! ===${NC}"
echo ""
echo "Add these to your tfvars file:"
echo ""
echo "langfuse_web_image    = \"${ECR_WEB_URL}:3\""
echo "langfuse_worker_image = \"${ECR_WORKER_URL}:3\""
echo "clickhouse_image      = \"${ECR_CLICKHOUSE_URL}:24\""
