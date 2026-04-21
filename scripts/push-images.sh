#!/bin/bash
# =============================================================================
# ClickHouse イメージを Docker Hub から ECR にプッシュする
# =============================================================================
# Langfuse Web / Worker は GitHub Actions (moji-inc/ai-eval) が自動ビルドする。
# ClickHouse は公式イメージをそのまま ECR にプッシュする（初回セットアップ時のみ実行）。
#
# 前提条件:
#   - AWS CLI が設定済みで ECR への push 権限があること
#   - Docker がインストールされていること
#   - terraform apply でECRリポジトリが作成済みであること
#
# 使い方:
#   ./scripts/push-images.sh <aws_account_id> <aws_region> [service_name]
#
# 例:
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
    echo -e "${RED}Usage: $0 <aws_account_id> <aws_region> [service_name]${NC}"
    echo "Example: $0 123456789012 ap-northeast-1 langfuse"
    exit 1
fi

AWS_ACCOUNT_ID="$1"
AWS_REGION="$2"
SERVICE_NAME="${3:-langfuse}"

ECR_BASE="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
CLICKHOUSE_SOURCE="clickhouse/clickhouse-server:24"
ECR_CLICKHOUSE_URL="${ECR_BASE}/${SERVICE_NAME}/clickhouse"
PLATFORM="linux/amd64"

echo -e "${GREEN}=== ClickHouse ECR Push Script ===${NC}"
echo "AWS Account: ${AWS_ACCOUNT_ID}"
echo "AWS Region:  ${AWS_REGION}"
echo "Service:     ${SERVICE_NAME}"
echo "Target:      ${ECR_CLICKHOUSE_URL}"
echo ""

# Login to ECR
echo -e "${YELLOW}Logging in to ECR...${NC}"
aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "${ECR_BASE}"

# Pull, tag, push
echo -e "${YELLOW}Pulling ${CLICKHOUSE_SOURCE} for ${PLATFORM}...${NC}"
docker pull --platform "${PLATFORM}" "${CLICKHOUSE_SOURCE}"

echo -e "${YELLOW}Pushing to ECR...${NC}"
docker tag "${CLICKHOUSE_SOURCE}" "${ECR_CLICKHOUSE_URL}:24"
docker tag "${CLICKHOUSE_SOURCE}" "${ECR_CLICKHOUSE_URL}:latest"
docker push "${ECR_CLICKHOUSE_URL}:24"
docker push "${ECR_CLICKHOUSE_URL}:latest"

echo ""
echo -e "${GREEN}=== ClickHouse image pushed successfully! ===${NC}"
