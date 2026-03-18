# RDS Maintenance Guide

## Scale Up (Instance Class Change)

### Via Terraform (Recommended)

1. Edit `tfvars/dev.tfvars`:

```hcl
db_instance_class = "db.t4g.small"  # Changed from db.t4g.micro
```

2. Apply changes:

```bash
cd infra
terraform plan -var-file=../tfvars/dev.tfvars
terraform apply -var-file=../tfvars/dev.tfvars
```

**Note**: Instance class change causes downtime (typically 5-15 minutes).

### Via AWS CLI

```bash
# Check current instance class
aws rds describe-db-instances \
  --db-instance-identifier langfuse-postgres \
  --query 'DBInstances[0].DBInstanceClass'

# Modify instance class (applies immediately)
aws rds modify-db-instance \
  --db-instance-identifier langfuse-postgres \
  --db-instance-class db.t4g.small \
  --apply-immediately

# Or schedule for next maintenance window
aws rds modify-db-instance \
  --db-instance-identifier langfuse-postgres \
  --db-instance-class db.t4g.small \
  --no-apply-immediately
```

### Instance Class Options

| Class | vCPU | Memory | Use Case |
|-------|------|--------|----------|
| db.t4g.micro | 2 | 1 GB | Development |
| db.t4g.small | 2 | 2 GB | Small production |
| db.t4g.medium | 2 | 4 GB | Medium production |
| db.t4g.large | 2 | 8 GB | Large production |
| db.r6g.large | 2 | 16 GB | Memory-intensive |

---

## Storage Scaling

### Increase Storage Size

Storage can only be increased, not decreased.

```bash
# Via AWS CLI
aws rds modify-db-instance \
  --db-instance-identifier langfuse-postgres \
  --allocated-storage 50 \
  --apply-immediately
```

Or update Terraform:

```hcl
# In rds.tf, add variable and change:
allocated_storage = 50  # GB
```

**Note**: Storage scaling has no downtime but may cause brief I/O latency.

---

## Enable Multi-AZ

### Via Terraform

1. Edit `tfvars/dev.tfvars`:

```hcl
db_multi_az = true
```

2. Apply:

```bash
terraform apply -var-file=../tfvars/dev.tfvars
```

### Via AWS CLI

```bash
aws rds modify-db-instance \
  --db-instance-identifier langfuse-postgres \
  --multi-az \
  --apply-immediately
```

**Note**: Enabling Multi-AZ causes brief downtime during failover setup.

---

## Maintenance Window Operations

### Check Current Maintenance Window

```bash
aws rds describe-db-instances \
  --db-instance-identifier langfuse-postgres \
  --query 'DBInstances[0].PreferredMaintenanceWindow'
```

### Change Maintenance Window

```bash
aws rds modify-db-instance \
  --db-instance-identifier langfuse-postgres \
  --preferred-maintenance-window "sun:03:00-sun:04:00"
```

### Check Pending Maintenance Actions

```bash
aws rds describe-pending-maintenance-actions \
  --resource-identifier arn:aws:rds:ap-northeast-1:ACCOUNT_ID:db:langfuse-postgres
```

### Apply Pending Maintenance Immediately

```bash
aws rds apply-pending-maintenance-action \
  --resource-identifier arn:aws:rds:ap-northeast-1:ACCOUNT_ID:db:langfuse-postgres \
  --apply-action system-update \
  --opt-in-type immediate
```

---

## Backup & Restore

### Create Manual Snapshot

```bash
aws rds create-db-snapshot \
  --db-instance-identifier langfuse-postgres \
  --db-snapshot-identifier langfuse-manual-$(date +%Y%m%d-%H%M%S)
```

### List Snapshots

```bash
aws rds describe-db-snapshots \
  --db-instance-identifier langfuse-postgres \
  --query 'DBSnapshots[*].[DBSnapshotIdentifier,SnapshotCreateTime,Status]' \
  --output table
```

### Restore from Snapshot

```bash
# Creates a NEW instance from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier langfuse-postgres-restored \
  --db-snapshot-identifier langfuse-manual-20240101-120000 \
  --db-instance-class db.t4g.micro
```

**Note**: Restoring creates a new instance. Update connection strings after restore.

---

## Point-in-Time Recovery

```bash
# Restore to specific time (creates new instance)
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier langfuse-postgres \
  --target-db-instance-identifier langfuse-postgres-pitr \
  --restore-time 2024-01-15T10:00:00Z
```

---

## Monitoring

### Check Instance Status

```bash
aws rds describe-db-instances \
  --db-instance-identifier langfuse-postgres \
  --query 'DBInstances[0].[DBInstanceStatus,DBInstanceClass,AllocatedStorage,MultiAZ]' \
  --output table
```

### View Recent Events

```bash
aws rds describe-events \
  --source-identifier langfuse-postgres \
  --source-type db-instance \
  --duration 1440
```

### Performance Insights (if enabled)

```bash
# Get DB load
aws pi get-resource-metrics \
  --service-type RDS \
  --identifier db-XXXXX \
  --metric-queries '[{"Metric": "db.load.avg"}]' \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period-in-seconds 60
```

---

## Reboot Instance

```bash
# Standard reboot
aws rds reboot-db-instance \
  --db-instance-identifier langfuse-postgres

# Force failover (Multi-AZ only)
aws rds reboot-db-instance \
  --db-instance-identifier langfuse-postgres \
  --force-failover
```

---

## Downtime Summary

| Operation | Downtime |
|-----------|----------|
| Instance class change | 5-15 minutes |
| Storage scaling | None (brief I/O latency) |
| Enable Multi-AZ | Brief (~1 minute) |
| Minor version upgrade | 5-10 minutes |
| Major version upgrade | 10-30 minutes |
| Reboot | 1-5 minutes |
| Snapshot creation | None |
| Restore from snapshot | N/A (new instance) |
