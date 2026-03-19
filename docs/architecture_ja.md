# Langfuse Self-Hosting on AWS - Architecture Design

## Overview

Langfuse v3 を AWS 上に self-hosting するためのアーキテクチャ設計書。
Terraform によるIaCでプロビジョニングする。

## Design Principles

- Kubernetes 不使用（ECS Fargate ベース）
- VPC 自動作成または既存 VPC を利用
- Security Group による IP 制限でアクセス制御
- ALB + ACM 証明書による HTTPS 対応（オプション）
- NAT Gateway 不使用、VPC Endpoints で AWS サービスにアクセス
- コンテナイメージは ECR から取得（事前に push が必要）
- ARM64 (Graviton) でコスト効率化
- シンプル構成を優先

---

## Architecture Diagram

### ALB なし（HTTP、動的 Public IP）

```
Internet
  │
  │  SG: allowed_cidrs → port 3000
  ▼
┌─────────────── VPC (自動作成または既存) ──────────────┐
│                                                        │
│  Public Subnet                                         │
│  └─ ECS Service: Langfuse Web (Public IP, 単一タスク)  │
│                                                        │
│  Private Subnets                                       │
│  ├─ ECS Service: Langfuse Worker (スケール可能)        │
│  ├─ ECS Service: ClickHouse     (固定1タスク)          │
│  │   └─ EFS (データ永続化)                              │
│  ├─ RDS PostgreSQL                                     │
│  ├─ ElastiCache Redis                                  │
│  └─ VPC Endpoints (ECR, Logs, Secrets Manager, S3)     │
└────────────────────────────────────────────────────────┘
```

### ALB あり（HTTPS、ACM 証明書が必要）

```
Internet
  │
  │  HTTPS:443 (ACM 証明書)
  ▼
┌─────────────── VPC (自動作成または既存) ──────────────┐
│                                                        │
│  Public Subnet                                         │
│  └─ ALB (Application Load Balancer)                    │
│                                                        │
│  Private Subnets                                       │
│  ├─ ECS Service: Langfuse Web (ALB 経由)               │
│  ├─ ECS Service: Langfuse Worker (スケール可能)        │
│  ├─ ECS Service: ClickHouse     (固定1タスク)          │
│  │   └─ EFS (データ永続化)                              │
│  ├─ RDS PostgreSQL                                     │
│  ├─ ElastiCache Redis                                  │
│  └─ VPC Endpoints (ECR, Logs, Secrets Manager, S3)     │
└────────────────────────────────────────────────────────┘
```

---

## Components

### Compute (ECS Fargate)

| Service | Image (ECR) | Port | Scaling | Subnet |
|---|---|---|---|---|
| Langfuse Web | `<account>.dkr.ecr.<region>.amazonaws.com/langfuse-dev/web:3` | 3000 | 単一タスク (desired_count=1) | Public |
| Langfuse Worker | `<account>.dkr.ecr.<region>.amazonaws.com/langfuse-dev/worker:3` | 3030 | ECS Service (desired_count 可変) | Private |
| ClickHouse | `<account>.dkr.ecr.<region>.amazonaws.com/langfuse-dev/clickhouse:24` | 8123 (HTTP), 9000 (TCP) | 固定 desired_count=1 | Private |

- **コンテナイメージは事前に ECR に push が必要**（`scripts/push-images.sh` を参照）
- Langfuse Web は Public Subnet に配置し、Public IP を自動割り当て（IP は動的）
- Worker は ECS Service の `desired_count` を調整してスケール可能
- ClickHouse はシングルインスタンス構成 (`CLICKHOUSE_CLUSTER_ENABLED=false`)
- ClickHouse のデータは EFS にマウントして永続化

### Database

| Service | AWS Resource | Details |
|---|---|---|
| PostgreSQL | RDS PostgreSQL | トランザクショナルDB (ユーザー、プロジェクト、APIキー等) |

- インスタンスクラスは変数化 (default: `db.t4g.micro`)
- Multi-AZ は変数で切り替え可能

### Cache / Queue

| Service | AWS Resource | Details |
|---|---|---|
| Redis | ElastiCache Redis | APIキャッシュ、プロンプトキャッシュ、ジョブキュー |

- ノードタイプは変数化 (default: `cache.t4g.micro`)

### Storage

| Service | AWS Resource | Details |
|---|---|---|
| Blob Storage | S3 | イベント永続化、マルチモーダルメディア、バッチエクスポート |

- VPC Gateway Endpoint 経由でアクセス

### VPC Endpoints（NAT Gateway 不要）

Private Subnet から AWS サービスへのアクセスには NAT Gateway ではなく VPC Endpoints を使用:

| Endpoint | タイプ | 用途 |
|---|---|---|
| ECR API | Interface | コンテナイメージメタデータ |
| ECR DKR | Interface | コンテナイメージ Pull (Docker Registry) |
| CloudWatch Logs | Interface | ECS タスクからのログ配信 |
| Secrets Manager | Interface | ECS タスクのシークレット取得 |
| S3 | Gateway | Blob ストレージアクセス（追加コストなし） |

---

## Network & Security

### コンポーネント配置とアクセス制御

| コンポーネント | Subnet | Public IP | Security Group 制限 |
|---|---|---|---|
| **Langfuse Web** | Public | Yes (動的) | `allowed_cidrs` から port 3000 のみ |
| **Langfuse Worker** | Private | No | Web からの Health check (3030) のみ |
| **ClickHouse** | Private | No | Web/Worker から 8123, 9000 のみ |
| **RDS PostgreSQL** | Private | No (`publicly_accessible = false`) | Web/Worker から 5432 のみ |
| **ElastiCache Redis** | Private | No | Web/Worker から 6379 のみ |
| **EFS** | Private | No | ClickHouse から 2049 のみ |

**セキュリティ設計の原則:**
- インターネットからアクセス可能なのは Langfuse Web のみ。かつ、指定した IP 範囲 (`allowed_cidrs`) からのアクセスに制限
- その他のコンポーネント (Worker, ClickHouse, RDS, Redis, EFS) はすべて Private Subnet に配置し、外部からのアクセスを遮断
- コンポーネント間の通信は Security Group で必要最小限に制限（最小権限の原則）

### Security Groups

| SG Name | Inbound Rule | Source | Description |
|---|---|---|---|
| `sg-web` | TCP 3000 | `var.allowed_cidrs` | 外部からのアクセス制限 |
| `sg-worker` | TCP 3030 | sg-web | ヘルスチェック用 |
| `sg-clickhouse` | TCP 8123, 9000 | sg-web, sg-worker | ClickHouse アクセス |
| `sg-rds` | TCP 5432 | sg-web, sg-worker | PostgreSQL アクセス |
| `sg-redis` | TCP 6379 | sg-web, sg-worker | Redis アクセス |
| `sg-efs` | TCP 2049 | sg-clickhouse | EFS マウント |

### Network Flow

```
[Client] → Langfuse Web (Public IP, Public Subnet, port 3000)
                → RDS PostgreSQL (Private Subnet)
                → ElastiCache Redis (Private Subnet)
                → ClickHouse ECS (Private Subnet)
                → S3 (VPC Endpoint)

Langfuse Worker (Private Subnet)
    → RDS PostgreSQL
    → ElastiCache Redis
    → ClickHouse ECS
    → S3 (VPC Endpoint)
```

---

## ECS Service Discovery (Cloud Map)

Langfuse Web / Worker から ClickHouse への接続には **ECS Service Discovery (AWS Cloud Map)** を使用する。

### 仕組み

1. Terraform で Cloud Map の**プライベート DNS 名前空間**を作成（例: `langfuse.local`）
   - 内部的に Route53 Private Hosted Zone が自動作成される
2. ClickHouse の ECS Service に Service Discovery を紐付け
   - サービス登録時に A レコードが自動登録される
3. ECS タスクの起動/停止時に Cloud Map が自動的に DNS レコードを更新
   - タスクの Private IP を登録/解除
4. Langfuse Web / Worker は `clickhouse.langfuse.local:8123` で名前解決し、ClickHouse に到達

### 特徴

- **VPC 内のみ**で名前解決可能（インターネットからは参照不可）
- **ECS が自動管理** — タスク再起動時も DNS レコードが自動で差し替わり、運用作業不要
- **TTL=10秒** — タスク再起動時に素早く切り替わるよう短めに設定
- **コスト** — Cloud Map はほぼ無料（月あたりのクエリ課金、微小）

### Terraform リソース

```hcl
# プライベート DNS 名前空間（Route53 Private Hosted Zone が自動作成される）
resource "aws_service_discovery_private_dns_namespace" "this" {
  name = "langfuse.local"
  vpc  = var.vpc_id
}

# ClickHouse 用のサービス登録
resource "aws_service_discovery_service" "clickhouse" {
  name = "clickhouse"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.this.id
    dns_records {
      type = "A"
      ttl  = 10
    }
  }
}

# ECS Service に紐付け
resource "aws_ecs_service" "clickhouse" {
  # ...
  service_registries {
    registry_arn = aws_service_discovery_service.clickhouse.arn
  }
}
```

### 環境変数での利用

| Variable | Value |
|---|---|
| `CLICKHOUSE_URL` | `http://clickhouse.langfuse.local:8123` |
| `CLICKHOUSE_MIGRATION_URL` | `clickhouse://clickhouse.langfuse.local:9000` |

---

## Environment Variables

### Langfuse Web / Worker 共通

| Variable | Source | Description |
|---|---|---|
| `DATABASE_URL` | Secrets Manager | PostgreSQL 接続文字列 |
| `DIRECT_URL` | Secrets Manager | マイグレーション用接続文字列 |
| `NEXTAUTH_SECRET` | Secrets Manager | セッション署名キー |
| `SALT` | Secrets Manager | APIキーハッシュソルト |
| `ENCRYPTION_KEY` | Secrets Manager | 256-bit hex 暗号化キー |
| `NEXTAUTH_URL` | 変数 | Langfuse Web の公開URL |
| `CLICKHOUSE_URL` | 内部 | `http://clickhouse.langfuse.local:8123` |
| `CLICKHOUSE_MIGRATION_URL` | 内部 | `clickhouse://clickhouse.langfuse.local:9000` |
| `CLICKHOUSE_USER` | Secrets Manager | ClickHouse ユーザー名 |
| `CLICKHOUSE_PASSWORD` | Secrets Manager | ClickHouse パスワード |
| `CLICKHOUSE_CLUSTER_ENABLED` | 固定 | `false` |
| `REDIS_CONNECTION_STRING` | 内部 | ElastiCache エンドポイント |
| `LANGFUSE_S3_EVENT_UPLOAD_BUCKET` | 変数 | S3 バケット名 |
| `LANGFUSE_S3_EVENT_UPLOAD_REGION` | 変数 | AWS リージョン |
| `HOSTNAME` | 固定 | `0.0.0.0` |

- S3 アクセスは IAM ロール (ECS タスクロール) を使用し、アクセスキーは不要

---

## Terraform Structure

```
infra/
├── main.tf              # provider, terraform settings, module calls
├── variables.tf         # 入力変数定義
├── locals.tf            # ローカル値（VPC ID, subnet IDs 等）
├── outputs.tf           # 出力値定義
├── vpc.tf               # VPC（vpc_id が null の場合に自動作成）
├── vpc_endpoints.tf     # VPC Endpoints (ECR, Logs, Secrets Manager)
├── security_groups.tf   # 全 Security Group 定義
├── iam.tf               # IAM Roles / Policies (ECS task role 等)
├── secrets.tf           # Secrets Manager (DB password, encryption keys 等)
└── modules/
    ├── langfuse/        # ECS Cluster, Web/Worker サービス, ElastiCache, S3
    ├── clickhouse/      # ClickHouse ECS サービス, EFS, Service Discovery
    └── rds/             # RDS PostgreSQL
```

### Key Variables

| Variable | Type | Description |
|---|---|---|
| `aws_region` | `string` | AWS リージョン |
| `service_name` | `string` | リソース命名プレフィックス (default: `langfuse`) |
| `user` | `string` | リソース識別用ユーザータグ |
| `vpc_id` | `string` | 既存 VPC ID (null = 自動作成) |
| `public_subnet_ids` | `list(string)` | Public Subnet IDs (vpc_id 指定時は必須) |
| `private_subnet_ids` | `list(string)` | Private Subnet IDs (vpc_id 指定時は必須) |
| `vpc_cidr` | `string` | 自動作成 VPC の CIDR (default: `10.0.0.0/16`) |
| `allowed_cidrs` | `list(string)` | アクセス許可 CIDR リスト |
| `langfuse_web_image` | `string` | Langfuse Web の ECR イメージ URL |
| `langfuse_worker_image` | `string` | Langfuse Worker の ECR イメージ URL |
| `clickhouse_image` | `string` | ClickHouse の ECR イメージ URL |
| `db_instance_class` | `string` | RDS インスタンスクラス (default: `db.t4g.micro`) |
| `db_name` | `string` | データベース名 (default: `langfuse`, ハイフン不可) |
| `cache_node_type` | `string` | ElastiCache ノードタイプ (default: `cache.t4g.micro`) |
| `web_cpu` | `number` | Web タスク CPU (default: `1024` = 1 vCPU) |
| `web_memory` | `number` | Web タスク メモリ (default: `2048` = 2 GB) |
| `worker_desired_count` | `number` | Langfuse Worker タスク数 (default: `1`) |
| `worker_cpu` | `number` | Worker タスク CPU (default: `1024`) |
| `worker_memory` | `number` | Worker タスク メモリ (default: `2048`) |
| `clickhouse_cpu` | `number` | ClickHouse タスク CPU (default: `2048` = 2 vCPU) |
| `clickhouse_memory` | `number` | ClickHouse タスク メモリ (default: `4096` = 4 GB) |
| `enable_alb` | `bool` | ALB を有効化して HTTPS アクセス (default: `false`) |
| `certificate_arn` | `string` | HTTPS 用 ACM 証明書 ARN (enable_alb = true の場合は必須) |

---

## Outputs

| Output | Description |
|---|---|
| `vpc_id` | VPC ID（作成または既存） |
| `public_subnet_ids` | Public subnet IDs |
| `private_subnet_ids` | Private subnet IDs |
| `ecs_cluster_name` | ECS クラスター名 |
| `langfuse_web_service_name` | Web サービス名（Public IP 取得に使用） |
| `rds_endpoint` | RDS PostgreSQL エンドポイント |
| `redis_endpoint` | ElastiCache Redis エンドポイント |
| `s3_bucket_name` | S3 バケット名 |
| `clickhouse_dns` | ClickHouse 内部 DNS 名 |
| `alb_dns_name` | ALB DNS 名（ALB 有効時） |
| `langfuse_url` | Langfuse アクセス URL |

---

## ALB 設定（オプション）

### オプション A: ALB + HTTP のみ（カスタムドメイン不要）

```hcl
enable_alb   = true
nextauth_url = "http://<alb-dns-name>"  # デプロイ後に設定
```

アクセス: `http://<alb-dns-name>`

### オプション B: ALB + HTTPS（カスタムドメインが必要）

1. **ACM 証明書を作成**:
   ```bash
   aws acm request-certificate \
     --domain-name langfuse.example.com \
     --validation-method DNS \
     --region us-east-1
   ```

2. **証明書を検証**（DNS に CNAME レコードを追加）

3. **tfvars を設定**:
   ```hcl
   enable_alb      = true
   certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/xxx"
   nextauth_url    = "https://langfuse.example.com"
   ```

4. **Terraform を適用**し、DNS を ALB に向ける

ALB 有効時:
- Langfuse Web は Private Subnet に移動（Public IP なし）
- 証明書あり: HTTP:80 は HTTPS:443 にリダイレクト
- 証明書なし: HTTP:80 のみ
- 通信経路: Internet → ALB → ECS (HTTP:3000)

---

## Future Considerations

- **固定IP**: NLB + Elastic IP の追加
- **カスタムドメイン**: Route53 で DNS レコード設定
- **Auto Scaling**: Web / Worker に ECS Service Auto Scaling (CPU/Memory ベース) を追加
- **監視**: CloudWatch Container Insights、RDS Performance Insights
- **バックアップ**: RDS 自動バックアップ、S3 バージョニング
- **Terraform remote state**: S3 + DynamoDB backend への移行
