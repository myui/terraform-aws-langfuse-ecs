# Langfuse Self-Hosting on AWS - Architecture Design

## Overview

Architecture design document for self-hosting Langfuse v3 on AWS.
Provisioned via Infrastructure as Code (IaC) using Terraform.

## Design Principles

- No Kubernetes (ECS Fargate-based)
- Auto-create VPC or use existing VPC
- Access control via Security Group IP restrictions
- HTTPS support via ALB + ACM certificate (optional)
- No NAT Gateway; use VPC Endpoints for AWS service access
- Container images from ECR (must be pushed beforehand)
- ARM64 (Graviton) for cost efficiency
- Prioritize simple configuration

---

## Architecture Diagram

### Without ALB (HTTP, dynamic Public IP)

```
Internet
  |
  |  SG: allowed_cidrs -> port 3000
  v
+------------------- VPC (auto-created or existing) ---+
|                                                      |
|  Public Subnet                                       |
|  +- ECS Service: Langfuse Web (Public IP, single task)|
|                                                      |
|  Private Subnets                                     |
|  +- ECS Service: Langfuse Worker (scalable)          |
|  +- ECS Service: ClickHouse     (fixed 1 task)       |
|  |   +- EFS (data persistence)                       |
|  +- RDS PostgreSQL                                   |
|  +- ElastiCache Redis                                |
|  +- VPC Endpoints (ECR, Logs, Secrets Manager, S3)   |
+------------------------------------------------------+
```

### With ALB (HTTPS, ACM certificate required)

```
Internet
  |
  |  HTTPS:443 (ACM certificate)
  v
+------------------- VPC (auto-created or existing) ---+
|                                                      |
|  Public Subnet                                       |
|  +- ALB (Application Load Balancer)                  |
|                                                      |
|  Private Subnets                                     |
|  +- ECS Service: Langfuse Web (behind ALB)           |
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

| Service | Image (ECR) | Port | Scaling | Subnet |
|---|---|---|---|---|
| Langfuse Web | `<account>.dkr.ecr.<region>.amazonaws.com/langfuse-dev/web:3` | 3000 | Single task (desired_count=1) | Public |
| Langfuse Worker | `<account>.dkr.ecr.<region>.amazonaws.com/langfuse-dev/worker:3` | 3030 | ECS Service (variable desired_count) | Private |
| ClickHouse | `<account>.dkr.ecr.<region>.amazonaws.com/langfuse-dev/clickhouse:24` | 8123 (HTTP), 9000 (TCP) | Fixed desired_count=1 | Private |

- **Container images must be pushed to ECR beforehand** (see `scripts/push-images.sh`)
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

#### Security Group Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Internet                                   │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                        ┌──────▼──────┐
                        │   ALB SG    │  443/tcp, 80/tcp ← allowed_cidrs
                        │  (Public)   │
                        └──────┬──────┘
                               │ 3000/tcp
                  ┌────────────▼────────────┐
                  │        Web SG           │  With ALB: from ALB only
                  │   (Private w/ ALB)      │  Without ALB: from allowed_cidrs
                  └────────────┬────────────┘
                               │
         ┌─────────────────────┼─────────────────────┐
         │                     │                     │
   ┌─────▼─────┐        ┌──────▼──────┐       ┌──────▼──────┐
   │ Worker SG │        │ ClickHouse  │       │  Redis SG   │
   │ 3030/tcp  │        │  SG         │       │  6379/tcp   │
   │ ← Web     │        │ 8123,9000   │       │ ← Web/Worker│
   └─────┬─────┘        │ ← Web/Worker│       └─────────────┘
         │              └──────┬──────┘
         │                     │
         │              ┌──────▼──────┐
         │              │   EFS SG    │
         │              │  2049/tcp   │
         │              │ ← ClickHouse│
         │              └─────────────┘
         │
   ┌─────▼─────┐
   │  RDS SG   │  5432/tcp ← Web/Worker only
   └───────────┘
```

#### Security Group Rules

| SG Name | Inbound Rule | Source | Egress | Description |
|---|---|---|---|---|
| `sg-alb` | TCP 443, 80 | `var.allowed_cidrs` (HTTP+HTTPS), `var.allowed_security_group_ids` (HTTPS only) | All | ALB for HTTPS termination |
| `sg-web` | TCP 3000 | sg-alb (with ALB) or `var.allowed_cidrs` (without ALB) | All | Langfuse Web application |
| `sg-worker` | TCP 3030 | sg-web | All | Worker health check endpoint |
| `sg-clickhouse` | TCP 8123, 9000 | sg-web, sg-worker | All | ClickHouse HTTP and native protocols |
| `sg-rds` | TCP 5432 | sg-web, sg-worker | None | PostgreSQL (no egress needed) |
| `sg-redis` | TCP 6379 | sg-web, sg-worker | None | Redis cache and queue |
| `sg-efs` | TCP 2049 | sg-clickhouse | None | EFS mount for ClickHouse data |
| `sg-vpc-endpoints` | TCP 443 | VPC CIDR | None | VPC Endpoints (ECR, Logs, Secrets Manager) |

#### Security Design Notes

- **ALB Security Group**: Only created when `enable_alb = true`. Restricts access to specified IP ranges (`allowed_cidrs`) and/or security groups (`allowed_security_group_ids`).
- **Web Security Group**: When ALB is enabled, direct access from `allowed_cidrs` is disabled. Traffic must go through ALB.
- **RDS Security Group**: No egress rules defined (RDS managed service does not require outbound connectivity).
- **Principle of Least Privilege**: Each component can only communicate with the specific services it needs.

### Network Flow

```
With ALB:
[Client] -> ALB (HTTPS:443) -> Langfuse Web (HTTP:3000, Private Subnet)
                                   -> RDS PostgreSQL (Private Subnet)
                                   -> ElastiCache Redis (Private Subnet)
                                   -> ClickHouse ECS (Private Subnet)
                                   -> S3 (VPC Endpoint)

Without ALB:
[Client] -> Langfuse Web (HTTP:3000, Public IP, Public Subnet)
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
├── main.tf              # provider, terraform settings, module calls
├── variables.tf         # Input variable definitions
├── locals.tf            # Local values (VPC ID, subnet IDs, etc.)
├── outputs.tf           # Output value definitions
├── vpc.tf               # VPC (auto-created when vpc_id is null)
├── vpc_endpoints.tf     # VPC Endpoints (ECR, Logs, Secrets Manager)
├── security_groups.tf   # All Security Group definitions
├── iam.tf               # IAM Roles / Policies (ECS task role, etc.)
├── secrets.tf           # Secrets Manager (DB password, encryption keys, etc.)
└── modules/
    ├── langfuse/        # ECS Cluster, Web/Worker services, ElastiCache, S3
    ├── clickhouse/      # ClickHouse ECS service, EFS, Service Discovery
    └── rds/             # RDS PostgreSQL
```

### Key Variables

| Variable | Type | Description |
|---|---|---|
| `aws_region` | `string` | AWS region |
| `service_name` | `string` | Resource naming prefix (default: `langfuse`) |
| `user` | `string` | User tag for resource identification |
| `vpc_id` | `string` | Existing VPC ID (null = auto-create) |
| `public_subnet_ids` | `list(string)` | Public Subnet IDs (required if vpc_id set) |
| `private_subnet_ids` | `list(string)` | Private Subnet IDs (required if vpc_id set) |
| `vpc_cidr` | `string` | CIDR for auto-created VPC (default: `10.0.0.0/16`) |
| `allowed_cidrs` | `list(string)` | Allowed CIDR list for access |
| `allowed_security_group_ids` | `list(string)` | Security group IDs allowed to access ALB via HTTPS only (for internal AWS services tracing, default: `[]`) |
| `langfuse_web_image` | `string` | ECR image URL for Langfuse Web |
| `langfuse_worker_image` | `string` | ECR image URL for Langfuse Worker |
| `clickhouse_image` | `string` | ECR image URL for ClickHouse |
| `db_instance_class` | `string` | RDS instance class (default: `db.t4g.micro`) |
| `db_name` | `string` | Database name (default: `langfuse`, no hyphens allowed) |
| `cache_node_type` | `string` | ElastiCache node type (default: `cache.t4g.micro`) |
| `web_cpu` | `number` | Web task CPU (default: `1024` = 1 vCPU) |
| `web_memory` | `number` | Web task memory (default: `2048` = 2 GB) |
| `worker_desired_count` | `number` | Langfuse Worker task count (default: `1`) |
| `worker_cpu` | `number` | Worker task CPU (default: `1024`) |
| `worker_memory` | `number` | Worker task memory (default: `2048`) |
| `clickhouse_cpu` | `number` | ClickHouse task CPU (default: `2048` = 2 vCPU) |
| `clickhouse_memory` | `number` | ClickHouse task memory (default: `4096` = 4 GB) |
| `enable_alb` | `bool` | Enable ALB for HTTPS access (default: `true`) |
| `certificate_arn` | `string` | ACM certificate ARN for HTTPS. If empty, self-signed certificate is used. |
| `custom_domain` | `string` | Custom domain for Langfuse (e.g., `langfuse.example.com`). Optional. |
| `route53_zone_id` | `string` | Route53 hosted zone ID. Required when custom_domain is set. |

---

## Outputs

| Output | Description |
|---|---|
| `vpc_id` | VPC ID (created or provided) |
| `public_subnet_ids` | Public subnet IDs |
| `private_subnet_ids` | Private subnet IDs |
| `ecs_cluster_name` | ECS cluster name |
| `langfuse_web_service_name` | Web service name (use to get Public IP) |
| `rds_endpoint` | RDS PostgreSQL endpoint |
| `redis_endpoint` | ElastiCache Redis endpoint |
| `s3_bucket_name` | S3 bucket name |
| `clickhouse_dns` | ClickHouse internal DNS name |
| `alb_dns_name` | ALB DNS name (when ALB is enabled) |
| `langfuse_url` | Langfuse access URL |

---

## ALB Configuration (Default: Enabled)

ALB is enabled by default (`enable_alb = true`). It provides HTTPS access with automatic certificate management.

### Certificate Options

| Configuration | Certificate | Access URL |
|---|---|---|
| Default (no `certificate_arn`) | Self-signed (auto-generated) | `https://<alb-dns-name>` (browser warning) |
| With `certificate_arn` | ACM certificate | `https://<alb-dns-name>` or custom domain |
| With `custom_domain` + `route53_zone_id` | ACM certificate | `https://langfuse.example.com` |

### Option A: Self-signed certificate (default, quickest setup)

```hcl
enable_alb = true
# certificate_arn not set - self-signed certificate will be generated
```

Access via: `https://<alb-dns-name>` (browser will show security warning)

**Note**: Self-signed certificates are suitable for development/testing. For production, use ACM certificate with a custom domain.

### Option B: ACM certificate (recommended for production)

1. **Create ACM certificate**:
   ```bash
   aws acm request-certificate \
     --domain-name langfuse.example.com \
     --validation-method DNS \
     --region us-east-1
   ```

2. **Validate certificate** via DNS (add CNAME record)

3. **Configure tfvars**:
   ```hcl
   enable_alb      = true
   certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/xxx"
   nextauth_url    = "https://langfuse.example.com"
   ```

4. **Apply Terraform** and configure DNS to point to ALB

### Option C: Custom domain with Route53 (fully automated DNS)

```hcl
enable_alb      = true
certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/xxx"
custom_domain   = "langfuse.example.com"
route53_zone_id = "Z1234567890ABC"
nextauth_url    = "https://langfuse.example.com"
```

Terraform will automatically create an A record alias in Route53.

### ALB Behavior

When ALB is enabled:
- Langfuse Web moves to Private Subnet (no public IP)
- HTTPS:443 is always enabled (ACM or self-signed certificate)
- Both HTTP:80 and HTTPS:443 forward to target group (both protocols accessible)
- Traffic flow: Internet → ALB (HTTPS) → ECS (HTTP:3000)

---

## Future Considerations

- **Static IP**: Add NLB + Elastic IP
- **Custom domain**: Configure DNS records in Route53
- **Auto Scaling**: Add ECS Service Auto Scaling (CPU/Memory-based) for Web / Worker
- **Monitoring**: CloudWatch Container Insights, RDS Performance Insights
- **Backup**: RDS automatic backup, S3 versioning
- **Terraform remote state**: Migrate to S3 + DynamoDB backend
