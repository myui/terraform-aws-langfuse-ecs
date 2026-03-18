# Langfuse Self-Hosting on AWS - Architecture Design

## Overview

Architecture design document for self-hosting Langfuse v3 on AWS.
Provisioned via Infrastructure as Code (IaC) using Terraform.

## Design Principles

- No Kubernetes (ECS Fargate-based)
- Use existing VPC
- Access control via Security Group IP restrictions
- HTTPS not required initially (can be added later)
- No Load Balancer; Langfuse Web placed directly in Public Subnet (dynamic Public IP)
- Prioritize simple configuration

---

## Architecture Diagram

```
Internet
  |
  |  SG: allowed_cidrs -> port 3000
  v
+------------------- Existing VPC ---------------------+
|                                                      |
|  Public Subnet (existing)                            |
|  +- ECS Service: Langfuse Web (Public IP, single task)|
|                                                      |
|  Private Subnets (existing)                          |
|  +- ECS Service: Langfuse Worker (scalable)          |
|  +- ECS Service: ClickHouse     (fixed 1 task)       |
|  |   +- EFS (data persistence)                       |
|  +- RDS PostgreSQL                                   |
|  +- ElastiCache Redis                                |
|  +- VPC Endpoints (ECR, Logs, Secrets Manager, S3)   |
+------------------------------------------------------+
```

---

## Components

### Compute (ECS Fargate)

| Service | Image | Port | Scaling | Subnet |
|---|---|---|---|---|
| Langfuse Web | `langfuse/langfuse:3` | 3000 | Single task (desired_count=1) | Public |
| Langfuse Worker | `langfuse/langfuse-worker:3` | 3030 | ECS Service (variable desired_count) | Private |
| ClickHouse | `clickhouse/clickhouse-server` | 8123 (HTTP), 9000 (TCP) | Fixed desired_count=1 | Private |

- Langfuse Web is placed in Public Subnet with auto-assigned Public IP (IP is dynamic)
- Worker can be scaled by adjusting ECS Service `desired_count`
- ClickHouse runs as single instance configuration (`CLICKHOUSE_CLUSTER_ENABLED=false`)
- ClickHouse data is persisted by mounting EFS

### Database

| Service | AWS Resource | Details |
|---|---|---|
| PostgreSQL | RDS PostgreSQL | Transactional DB (users, projects, API keys, etc.) |

- Instance class is configurable (default: `db.t4g.micro`)
- Multi-AZ can be toggled via variable

### Cache / Queue

| Service | AWS Resource | Details |
|---|---|---|
| Redis | ElastiCache Redis | API cache, prompt cache, job queue |

- Node type is configurable (default: `cache.t4g.micro`)

### Storage

| Service | AWS Resource | Details |
|---|---|---|
| Blob Storage | S3 | Event persistence, multimodal media, batch exports |

- Accessed via VPC Gateway Endpoint

### VPC Endpoints (No NAT Gateway)

Private subnets use VPC Endpoints instead of NAT Gateway for AWS service access:

| Endpoint | Type | Purpose |
|---|---|---|
| ECR API | Interface | Container image metadata |
| ECR DKR | Interface | Container image pull (Docker Registry) |
| CloudWatch Logs | Interface | Log delivery from ECS tasks |
| Secrets Manager | Interface | Secret retrieval for ECS tasks |
| S3 | Gateway | Blob storage access (no additional cost) |

---

## Network & Security

### Component Placement & Access Control

| Component | Subnet | Public IP | Security Group Restrictions |
|---|---|---|---|
| **Langfuse Web** | Public | Yes (dynamic) | Only port 3000 from `allowed_cidrs` |
| **Langfuse Worker** | Private | No | Only health check (3030) from Web |
| **ClickHouse** | Private | No | Only 8123, 9000 from Web/Worker |
| **RDS PostgreSQL** | Private | No (`publicly_accessible = false`) | Only 5432 from Web/Worker |
| **ElastiCache Redis** | Private | No | Only 6379 from Web/Worker |
| **EFS** | Private | No | Only 2049 from ClickHouse |

**Security Design Principles:**
- Only Langfuse Web is accessible from the internet, and access is restricted to specified IP ranges (`allowed_cidrs`)
- All other components (Worker, ClickHouse, RDS, Redis, EFS) are placed in Private Subnets with no public accessibility
- Inter-component communication is restricted via Security Groups, following the principle of least privilege

### Security Groups

| SG Name | Inbound Rule | Source | Description |
|---|---|---|---|
| `sg-web` | TCP 3000 | `var.allowed_cidrs` | External access restriction |
| `sg-worker` | TCP 3030 | sg-web | Health check |
| `sg-clickhouse` | TCP 8123, 9000 | sg-web, sg-worker | ClickHouse access |
| `sg-rds` | TCP 5432 | sg-web, sg-worker | PostgreSQL access |
| `sg-redis` | TCP 6379 | sg-web, sg-worker | Redis access |
| `sg-efs` | TCP 2049 | sg-clickhouse | EFS mount |

### Network Flow

```
[Client] -> Langfuse Web (Public IP, Public Subnet, port 3000)
                -> RDS PostgreSQL (Private Subnet)
                -> ElastiCache Redis (Private Subnet)
                -> ClickHouse ECS (Private Subnet)
                -> S3 (VPC Endpoint)

Langfuse Worker (Private Subnet)
    -> RDS PostgreSQL
    -> ElastiCache Redis
    -> ClickHouse ECS
    -> S3 (VPC Endpoint)
```

---

## ECS Service Discovery (Cloud Map)

**ECS Service Discovery (AWS Cloud Map)** is used for connections from Langfuse Web / Worker to ClickHouse.

### How It Works

1. Terraform creates a Cloud Map **private DNS namespace** (e.g., `langfuse.local`)
   - A Route53 Private Hosted Zone is automatically created internally
2. Service Discovery is associated with the ClickHouse ECS Service
   - An A record is automatically registered when the service is registered
3. Cloud Map automatically updates DNS records when ECS tasks start/stop
   - Registers/deregisters task Private IPs
4. Langfuse Web / Worker resolves `clickhouse.langfuse.local:8123` to reach ClickHouse

### Characteristics

- Name resolution is **only available within VPC** (not accessible from internet)
- **Managed automatically by ECS** — DNS records are automatically replaced on task restart, no operational work required
- **TTL=10 seconds** — Set short for quick switchover on task restart
- **Cost** — Cloud Map is nearly free (per-query billing, minimal)

### Terraform Resources

```hcl
# Private DNS namespace (Route53 Private Hosted Zone is auto-created)
resource "aws_service_discovery_private_dns_namespace" "this" {
  name = "langfuse.local"
  vpc  = var.vpc_id
}

# Service registration for ClickHouse
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

# Associate with ECS Service
resource "aws_ecs_service" "clickhouse" {
  # ...
  service_registries {
    registry_arn = aws_service_discovery_service.clickhouse.arn
  }
}
```

### Environment Variable Usage

| Variable | Value |
|---|---|
| `CLICKHOUSE_URL` | `http://clickhouse.langfuse.local:8123` |
| `CLICKHOUSE_MIGRATION_URL` | `clickhouse://clickhouse.langfuse.local:9000` |

---

## Environment Variables

### Common to Langfuse Web / Worker

| Variable | Source | Description |
|---|---|---|
| `DATABASE_URL` | Secrets Manager | PostgreSQL connection string |
| `DIRECT_URL` | Secrets Manager | Connection string for migrations |
| `NEXTAUTH_SECRET` | Secrets Manager | Session signing key |
| `SALT` | Secrets Manager | API key hash salt |
| `ENCRYPTION_KEY` | Secrets Manager | 256-bit hex encryption key |
| `NEXTAUTH_URL` | Variable | Langfuse Web public URL |
| `CLICKHOUSE_URL` | Internal | `http://clickhouse.langfuse.local:8123` |
| `CLICKHOUSE_MIGRATION_URL` | Internal | `clickhouse://clickhouse.langfuse.local:9000` |
| `CLICKHOUSE_USER` | Secrets Manager | ClickHouse username |
| `CLICKHOUSE_PASSWORD` | Secrets Manager | ClickHouse password |
| `CLICKHOUSE_CLUSTER_ENABLED` | Fixed | `false` |
| `REDIS_CONNECTION_STRING` | Internal | ElastiCache endpoint |
| `LANGFUSE_S3_EVENT_UPLOAD_BUCKET` | Variable | S3 bucket name |
| `LANGFUSE_S3_EVENT_UPLOAD_REGION` | Variable | AWS region |
| `HOSTNAME` | Fixed | `0.0.0.0` |

- S3 access uses IAM role (ECS task role), no access keys required

---

## Terraform Structure

```
infra/
├── main.tf              # provider, terraform settings
├── variables.tf         # Input variable definitions
├── outputs.tf           # Output value definitions
├── ecs.tf               # ECS Cluster + 3 Services (web, worker, clickhouse)
├── rds.tf               # RDS PostgreSQL
├── elasticache.tf       # ElastiCache Redis
├── s3.tf                # S3 Bucket + VPC Endpoint
├── efs.tf               # EFS (ClickHouse persistence)
├── security_groups.tf   # All Security Group definitions
├── iam.tf               # IAM Roles / Policies (ECS task role, etc.)
├── secrets.tf           # Secrets Manager (DB password, encryption keys, etc.)
└── service_discovery.tf # Cloud Map (ClickHouse DNS)
```

### Key Variables

| Variable | Type | Description |
|---|---|---|
| `vpc_id` | `string` | Existing VPC ID |
| `public_subnet_ids` | `list(string)` | Public Subnet IDs for Langfuse Web placement |
| `private_subnet_ids` | `list(string)` | Private Subnet IDs for Worker / ClickHouse / RDS / ElastiCache |
| `allowed_cidrs` | `list(string)` | Allowed CIDR list for access |
| `db_instance_class` | `string` | RDS instance class (default: `db.t4g.micro`) |
| `db_name` | `string` | Database name (default: `langfuse`) |
| `cache_node_type` | `string` | ElastiCache node type (default: `cache.t4g.micro`) |
| `worker_desired_count` | `number` | Langfuse Worker task count (default: `1`) |
| `web_cpu` | `number` | Web task CPU (default: `1024` = 1 vCPU) |
| `web_memory` | `number` | Web task memory (default: `2048` = 2 GB) |
| `worker_cpu` | `number` | Worker task CPU (default: `1024`) |
| `worker_memory` | `number` | Worker task memory (default: `2048`) |
| `clickhouse_cpu` | `number` | ClickHouse task CPU (default: `2048` = 2 vCPU) |
| `clickhouse_memory` | `number` | ClickHouse task memory (default: `4096` = 4 GB) |
| `aws_region` | `string` | AWS region |
| `project_name` | `string` | Resource naming prefix (default: `langfuse`) |

---

## Outputs

| Output | Description |
|---|---|
| `langfuse_web_public_ip` | Langfuse Web Public IP (dynamic, changes on task restart) |
| `langfuse_url` | Langfuse Web access URL (`http://<public_ip>:3000`) |
| `rds_endpoint` | RDS PostgreSQL endpoint |
| `redis_endpoint` | ElastiCache Redis endpoint |
| `s3_bucket_name` | S3 bucket name |

---

## Future Considerations

- **HTTPS support**: Add ALB + ACM certificate
- **Static IP**: Add NLB + Elastic IP
- **Custom domain**: Configure DNS records in Route53
- **Auto Scaling**: Add ECS Service Auto Scaling (CPU/Memory-based) for Web / Worker
- **Monitoring**: CloudWatch Container Insights, RDS Performance Insights
- **Backup**: RDS automatic backup, S3 versioning
- **Terraform remote state**: Migrate to S3 + DynamoDB backend
