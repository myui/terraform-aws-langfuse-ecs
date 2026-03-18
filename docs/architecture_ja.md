# Langfuse Self-Hosting on AWS - Architecture Design

## Overview

Langfuse v3 を AWS 上に self-hosting するためのアーキテクチャ設計書。
Terraform によるIaCでプロビジョニングする。

## Design Principles

- Kubernetes 不使用（ECS Fargate ベース）
- 既存 VPC を利用
- Security Group による IP 制限でアクセス制御
- HTTPS は初期段階では不要（後日対応可能）
- LB 不使用、Langfuse Web は Public Subnet に直接配置（Public IP 動的）
- シンプル構成を優先

---

## Architecture Diagram

```
Internet
  │
  │  SG: allowed_cidrs → port 3000
  ▼
┌─────────────────── Existing VPC ──────────────────────┐
│                                                        │
│  Public Subnet (既存)                                  │
│  └─ ECS Service: Langfuse Web (Public IP, 単一タスク)  │
│                                                        │
│  Private Subnets (既存, NAT Gateway あり)              │
│  ├─ ECS Service: Langfuse Worker (スケール可能)        │
│  ├─ ECS Service: ClickHouse     (固定1タスク)          │
│  │   └─ EFS (データ永続化)                              │
│  ├─ RDS PostgreSQL                                     │
│  ├─ ElastiCache Redis                                  │
│  └─ S3 VPC Endpoint (Gateway)                          │
└────────────────────────────────────────────────────────┘
```

---

## Components

### Compute (ECS Fargate)

| Service | Image | Port | Scaling | Subnet |
|---|---|---|---|---|
| Langfuse Web | `langfuse/langfuse:3` | 3000 | 単一タスク (desired_count=1) | Public |
| Langfuse Worker | `langfuse/langfuse-worker:3` | 3030 | ECS Service (desired_count 可変) | Private |
| ClickHouse | `clickhouse/clickhouse-server` | 8123 (HTTP), 9000 (TCP) | 固定 desired_count=1 | Private |

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

- VPC Gateway Endpoint 経由でアクセス (NAT Gateway 経由の通信コスト回避)

---

## Network & Security

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
├── main.tf              # provider, terraform settings
├── variables.tf         # 入力変数定義
├── outputs.tf           # 出力値定義
├── ecs.tf               # ECS Cluster + 3 Services (web, worker, clickhouse)
├── rds.tf               # RDS PostgreSQL
├── elasticache.tf       # ElastiCache Redis
├── s3.tf                # S3 Bucket + VPC Endpoint
├── efs.tf               # EFS (ClickHouse 永続化)
├── security_groups.tf   # 全 Security Group 定義
├── iam.tf               # IAM Roles / Policies (ECS task role 等)
├── secrets.tf           # Secrets Manager (DB password, encryption keys 等)
└── service_discovery.tf # Cloud Map (ClickHouse DNS)
```

### Key Variables

| Variable | Type | Description |
|---|---|---|
| `vpc_id` | `string` | 既存 VPC ID |
| `public_subnet_ids` | `list(string)` | Langfuse Web 配置用 Public Subnet IDs |
| `private_subnet_ids` | `list(string)` | Worker / ClickHouse / RDS / ElastiCache 用 Private Subnet IDs |
| `allowed_cidrs` | `list(string)` | アクセス許可 CIDR リスト |
| `db_instance_class` | `string` | RDS インスタンスクラス (default: `db.t4g.micro`) |
| `db_name` | `string` | データベース名 (default: `langfuse`) |
| `cache_node_type` | `string` | ElastiCache ノードタイプ (default: `cache.t4g.micro`) |
| `worker_desired_count` | `number` | Langfuse Worker タスク数 (default: `1`) |
| `web_cpu` | `number` | Web タスク CPU (default: `1024` = 1 vCPU) |
| `web_memory` | `number` | Web タスク メモリ (default: `2048` = 2 GB) |
| `worker_cpu` | `number` | Worker タスク CPU (default: `1024`) |
| `worker_memory` | `number` | Worker タスク メモリ (default: `2048`) |
| `clickhouse_cpu` | `number` | ClickHouse タスク CPU (default: `2048` = 2 vCPU) |
| `clickhouse_memory` | `number` | ClickHouse タスク メモリ (default: `4096` = 4 GB) |
| `aws_region` | `string` | AWS リージョン |
| `project_name` | `string` | リソース命名プレフィックス (default: `langfuse`) |

---

## Outputs

| Output | Description |
|---|---|
| `langfuse_web_public_ip` | Langfuse Web の Public IP（動的、タスク再起動で変更） |
| `langfuse_url` | Langfuse Web アクセス URL (`http://<public_ip>:3000`) |
| `rds_endpoint` | RDS PostgreSQL エンドポイント |
| `redis_endpoint` | ElastiCache Redis エンドポイント |
| `s3_bucket_name` | S3 バケット名 |

---

## Future Considerations

- **HTTPS 対応**: ALB 追加 + ACM 証明書
- **固定IP**: NLB + Elastic IP の追加
- **カスタムドメイン**: Route53 で DNS レコード設定
- **Auto Scaling**: Web / Worker に ECS Service Auto Scaling (CPU/Memory ベース) を追加
- **監視**: CloudWatch Container Insights、RDS Performance Insights
- **バックアップ**: RDS 自動バックアップ、S3 バージョニング
- **Terraform remote state**: S3 + DynamoDB backend への移行
