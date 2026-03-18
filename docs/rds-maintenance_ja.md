# RDS メンテナンスガイド

## スケールアップ（インスタンスクラス変更）

### Terraform 経由（推奨）

1. `tfvars/dev.tfvars` を編集:

```hcl
db_instance_class = "db.t4g.small"  # db.t4g.micro から変更
```

2. 変更を適用:

```bash
cd infra
terraform plan -var-file=../tfvars/dev.tfvars
terraform apply -var-file=../tfvars/dev.tfvars
```

**注意**: インスタンスクラス変更にはダウンタイムが発生します（通常 5〜15 分）。

### AWS CLI 経由

```bash
# 現在のインスタンスクラスを確認
aws rds describe-db-instances \
  --db-instance-identifier langfuse-postgres \
  --query 'DBInstances[0].DBInstanceClass'

# インスタンスクラスを変更（即時適用）
aws rds modify-db-instance \
  --db-instance-identifier langfuse-postgres \
  --db-instance-class db.t4g.small \
  --apply-immediately

# または次回メンテナンスウィンドウで適用
aws rds modify-db-instance \
  --db-instance-identifier langfuse-postgres \
  --db-instance-class db.t4g.small \
  --no-apply-immediately
```

### インスタンスクラス一覧

| クラス | vCPU | メモリ | 用途 |
|--------|------|--------|------|
| db.t4g.micro | 2 | 1 GB | 開発環境 |
| db.t4g.small | 2 | 2 GB | 小規模本番 |
| db.t4g.medium | 2 | 4 GB | 中規模本番 |
| db.t4g.large | 2 | 8 GB | 大規模本番 |
| db.r6g.large | 2 | 16 GB | メモリ集約型 |

---

## ストレージスケーリング

### ストレージサイズの増加

ストレージは増加のみ可能で、縮小はできません。

```bash
# AWS CLI 経由
aws rds modify-db-instance \
  --db-instance-identifier langfuse-postgres \
  --allocated-storage 50 \
  --apply-immediately
```

または Terraform を更新:

```hcl
# rds.tf で変数を追加して変更:
allocated_storage = 50  # GB
```

**注意**: ストレージスケーリングにダウンタイムはありませんが、一時的に I/O レイテンシが発生する場合があります。

---

## Multi-AZ の有効化

### Terraform 経由

1. `tfvars/dev.tfvars` を編集:

```hcl
db_multi_az = true
```

2. 適用:

```bash
terraform apply -var-file=../tfvars/dev.tfvars
```

### AWS CLI 経由

```bash
aws rds modify-db-instance \
  --db-instance-identifier langfuse-postgres \
  --multi-az \
  --apply-immediately
```

**注意**: Multi-AZ 有効化時、フェイルオーバー設定中に短時間のダウンタイムが発生します。

---

## メンテナンスウィンドウ操作

### 現在のメンテナンスウィンドウを確認

```bash
aws rds describe-db-instances \
  --db-instance-identifier langfuse-postgres \
  --query 'DBInstances[0].PreferredMaintenanceWindow'
```

### メンテナンスウィンドウの変更

```bash
aws rds modify-db-instance \
  --db-instance-identifier langfuse-postgres \
  --preferred-maintenance-window "sun:03:00-sun:04:00"
```

### 保留中のメンテナンスアクションを確認

```bash
aws rds describe-pending-maintenance-actions \
  --resource-identifier arn:aws:rds:ap-northeast-1:ACCOUNT_ID:db:langfuse-postgres
```

### 保留中のメンテナンスを即時適用

```bash
aws rds apply-pending-maintenance-action \
  --resource-identifier arn:aws:rds:ap-northeast-1:ACCOUNT_ID:db:langfuse-postgres \
  --apply-action system-update \
  --opt-in-type immediate
```

---

## バックアップとリストア

### 手動スナップショットの作成

```bash
aws rds create-db-snapshot \
  --db-instance-identifier langfuse-postgres \
  --db-snapshot-identifier langfuse-manual-$(date +%Y%m%d-%H%M%S)
```

### スナップショット一覧

```bash
aws rds describe-db-snapshots \
  --db-instance-identifier langfuse-postgres \
  --query 'DBSnapshots[*].[DBSnapshotIdentifier,SnapshotCreateTime,Status]' \
  --output table
```

### スナップショットからリストア

```bash
# スナップショットから新しいインスタンスを作成
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier langfuse-postgres-restored \
  --db-snapshot-identifier langfuse-manual-20240101-120000 \
  --db-instance-class db.t4g.micro
```

**注意**: リストアは新しいインスタンスを作成します。リストア後に接続文字列の更新が必要です。

---

## ポイントインタイムリカバリ

```bash
# 特定時点にリストア（新しいインスタンスを作成）
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier langfuse-postgres \
  --target-db-instance-identifier langfuse-postgres-pitr \
  --restore-time 2024-01-15T10:00:00Z
```

---

## モニタリング

### インスタンスステータスの確認

```bash
aws rds describe-db-instances \
  --db-instance-identifier langfuse-postgres \
  --query 'DBInstances[0].[DBInstanceStatus,DBInstanceClass,AllocatedStorage,MultiAZ]' \
  --output table
```

### 最近のイベントを確認

```bash
aws rds describe-events \
  --source-identifier langfuse-postgres \
  --source-type db-instance \
  --duration 1440
```

### Performance Insights（有効化している場合）

```bash
# DB 負荷を取得
aws pi get-resource-metrics \
  --service-type RDS \
  --identifier db-XXXXX \
  --metric-queries '[{"Metric": "db.load.avg"}]' \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period-in-seconds 60
```

---

## インスタンスの再起動

```bash
# 通常の再起動
aws rds reboot-db-instance \
  --db-instance-identifier langfuse-postgres

# 強制フェイルオーバー（Multi-AZ のみ）
aws rds reboot-db-instance \
  --db-instance-identifier langfuse-postgres \
  --force-failover
```

---

## ダウンタイム一覧

| 操作 | ダウンタイム |
|------|-------------|
| インスタンスクラス変更 | 5〜15 分 |
| ストレージスケーリング | なし（一時的な I/O レイテンシ） |
| Multi-AZ 有効化 | 短時間（約 1 分） |
| マイナーバージョンアップグレード | 5〜10 分 |
| メジャーバージョンアップグレード | 10〜30 分 |
| 再起動 | 1〜5 分 |
| スナップショット作成 | なし |
| スナップショットからリストア | N/A（新規インスタンス） |
