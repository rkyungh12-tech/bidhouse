#!/usr/bin/env bash
# ============================================================
# [scripts/db-replicate.sh] RDS → Azure MySQL 단방향 복제 설정
# buildspec.yml STAGE 3에서 테라폼 apply 완료 후 호출
# ============================================================
set -euo pipefail
set -x

echo "========================================"
echo "  DB 복제 시작 (RDS → Azure MySQL)"
echo "========================================"

# ── 1. Terraform output에서 값 가져오기 ──────────────────────
cd "$CODEBUILD_SRC_DIR/02-azure-singapore-dr"
terraform init -reconfigure \
  -backend-config="bucket=bidhouse-global-immutable-2026" \
  -backend-config="region=ap-northeast-2" \
  -backend-config="encrypt=true" > /dev/null 2>&1

AZ_KV_NAME=$(terraform output -raw azure_key_vault_name)
AZ_MYSQL_FQDN=$(terraform output -raw azure_mysql_fqdn)

# ── 2. Azure MySQL Private IP 조회 → /etc/hosts 등록 ─────────
AZ_MYSQL_IP=$(az network private-dns record-set a list \
  --resource-group "bidhouse-dr-v1-rg" \
  --zone-name "bidhouse.mysql.database.azure.com" \
  --query "[0].aRecords[0].ipv4Address" -o tsv 2>/dev/null || echo "")

if [ -n "$AZ_MYSQL_IP" ]; then
  echo "$AZ_MYSQL_IP $AZ_MYSQL_FQDN" >> /etc/hosts
  echo "✅ hosts 등록: $AZ_MYSQL_IP → $AZ_MYSQL_FQDN"
else
  echo "⚠️ IP 조회 실패, FQDN 직접 사용"
fi

# ── 3. RDS 접속 정보 가져오기 ─────────────────────────────────
cd "$CODEBUILD_SRC_DIR/01-aws-seoul-network"
terraform init -reconfigure \
  -backend-config="bucket=bidhouse-global-immutable-2026" \
  -backend-config="region=ap-northeast-2" \
  -backend-config="encrypt=true" > /dev/null 2>&1

RDS_SECRET_ARN=$(terraform output -raw rds_master_secret_arn)
RDS_HOST=$(terraform output -raw rds_endpoint)

AZURE_MYSQL_ADMIN=$(az keyvault secret show \
  --vault-name "$AZ_KV_NAME" --name mysql-admin-username \
  --query value -o tsv)
AZURE_MYSQL_ADMIN_PASS=$(az keyvault secret show \
  --vault-name "$AZ_KV_NAME" --name mysql-admin-password \
  --query value -o tsv)

RDS_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "$RDS_SECRET_ARN" \
  --query SecretString --output text)
RDS_USER=$(echo "$RDS_SECRET" | jq -r '.username')
RDS_PASS=$(echo "$RDS_SECRET" | jq -r '.password')

cat > /tmp/az_mycnf <<EOF
[client]
user=$AZURE_MYSQL_ADMIN
password="$AZURE_MYSQL_ADMIN_PASS"
EOF
cat > /tmp/aws_mycnf <<EOF
[client]
user=$RDS_USER
password="$RDS_PASS"
EOF

# ── [13-0] repl_user 비밀번호 (최초 1회 생성, 이후 재사용) ──────
echo "=== [13-0] repl_user 비밀번호 확인 ==="
REPL_PASS=$(aws secretsmanager get-secret-value \
  --secret-id "bidhouse-repl-user-password" \
  --region ap-northeast-2 \
  --query SecretString --output text 2>/dev/null || echo "")

if [ -z "$REPL_PASS" ]; then
  REPL_PASS="Repl@$(openssl rand -hex 8)"
  aws secretsmanager create-secret \
    --name "bidhouse-repl-user-password" \
    --secret-string "$REPL_PASS" \
    --region ap-northeast-2
  echo "✅ 복제 비밀번호 신규 생성 완료"
else
  echo "✅ 기존 복제 비밀번호 재사용"
fi

# ── [13-1] RDS 복제 계정 생성 ────────────────────────────────
echo "=== [13-1] RDS 복제 계정 생성 ==="
mysql --defaults-file="/tmp/aws_mycnf" -h "$RDS_HOST" -e "
  CREATE USER IF NOT EXISTS 'repl_user'@'%' IDENTIFIED BY '$REPL_PASS';
  GRANT REPLICATION SLAVE ON *.* TO 'repl_user'@'%';
  ALTER USER 'repl_user'@'%' IDENTIFIED BY '$REPL_PASS';
  FLUSH PRIVILEGES;
"

# ── [13-2] 복제 상태 확인 → 이미 실행 중이면 건너뜀 ──────────
echo "=== [13-2] 초기 데이터 덤프 및 Azure MySQL 적재 ==="
EXISTING_SLAVE_STATUS=$(mysql --defaults-file="/tmp/az_mycnf" \
  -h "$AZ_MYSQL_FQDN" --ssl-mode=REQUIRED -e "SHOW SLAVE STATUS\G" 2>/dev/null || echo "")
EXISTING_IO=$(echo "$EXISTING_SLAVE_STATUS" | awk '/Slave_IO_Running:/ {print $2}')
EXISTING_SQL=$(echo "$EXISTING_SLAVE_STATUS" | awk '/Slave_SQL_Running:/ {print $2}')
EXISTING_MASTER_HOST=$(echo "$EXISTING_SLAVE_STATUS" | awk '/Master_Host:/ {print $2}')

if [ "$EXISTING_IO" = "Yes" ] && [ "$EXISTING_SQL" = "Yes" ] && [ "$EXISTING_MASTER_HOST" = "$RDS_HOST" ]; then
  echo "✅ 복제 이미 정상 동작 중(Yes/Yes) → 재덤프/재연결 없이 건너뜀"
else
  # binlog 위치 먼저 별도 조회
  echo "📦 binlog 위치 조회 중..."
  MASTER_STATUS=$(mysql --defaults-file="/tmp/aws_mycnf" \
    -h "$RDS_HOST" -e "SHOW MASTER STATUS\G")
  BINLOG_FILE=$(echo "$MASTER_STATUS" | awk '/File:/ {print $2}')
  BINLOG_POS=$(echo "$MASTER_STATUS" | awk '/Position:/ {print $2}')
  echo "📍 binlog 위치: $BINLOG_FILE @ $BINLOG_POS"

  echo "📦 mysqldump 시작..."
  mysqldump --defaults-file="/tmp/aws_mycnf" \
    -h "$RDS_HOST" \
    --single-transaction \
    --set-gtid-purged=OFF \
    --no-tablespaces \
    --routines --triggers \
    --ignore-table=auction.chat_messages \
    auction > /tmp/auction_dump.sql

  echo "📥 Azure MySQL에 덤프 적재 중..."
  mysql --defaults-file="/tmp/az_mycnf" \
    -h "$AZ_MYSQL_FQDN" --ssl-mode=REQUIRED \
    auction < /tmp/auction_dump.sql

  # ── [13-3] 복제 채널 연결 ──────────────────────────────────
  echo "=== [13-3] 복제 채널 연결 ==="
  mysql --defaults-file="/tmp/az_mycnf" \
    -h "$AZ_MYSQL_FQDN" --ssl-mode=REQUIRED -e \
    "CALL mysql.az_replication_change_master(
      '$RDS_HOST', 'repl_user', '$REPL_PASS',
      3306, '$BINLOG_FILE', $BINLOG_POS, '');"

  mysql --defaults-file="/tmp/az_mycnf" \
    -h "$AZ_MYSQL_FQDN" --ssl-mode=REQUIRED -e \
    "CALL mysql.az_replication_start();"

  # ── [13-4] 복제 상태 확인 ──────────────────────────────────
  # ── [13-4] 복제 상태 확인 + 자동 Skip 재시도 ──────────────────
  echo "=== [13-4] 복제 상태 확인 (자동 Skip 루프) ==="
  sleep 10

  for i in $(seq 1 30); do
    SLAVE_STATUS=$(mysql --defaults-file="/tmp/az_mycnf" \
      -h "$AZ_MYSQL_FQDN" --ssl-mode=REQUIRED -e "SHOW SLAVE STATUS\G")

    SQL_RUNNING=$(echo "$SLAVE_STATUS" | awk '/Slave_SQL_Running:/ {print $2}')
    LAST_SQL_ERRNO=$(echo "$SLAVE_STATUS" | awk '/Last_SQL_Errno:/ {print $2}')

    echo "[$i/30] Slave_SQL_Running=$SQL_RUNNING Last_SQL_Errno=$LAST_SQL_ERRNO"

    if [ "$SQL_RUNNING" = "Yes" ]; then
      echo "✅ 복제 정상 동작 중"
      break
    fi

    if [ -n "$LAST_SQL_ERRNO" ] && [ "$LAST_SQL_ERRNO" != "0" ]; then
      echo "⚠️ SQL 에러 감지 (Errno: $LAST_SQL_ERRNO) → 자동 Skip 후 재시작"
      mysql --defaults-file="/tmp/az_mycnf" \
        -h "$AZ_MYSQL_FQDN" --ssl-mode=REQUIRED -e \
        "CALL mysql.az_replication_skip_counter();" || true
      sleep 5
    else
      echo "⏳ 복제 상태 점검 중... 5초 대기"
      sleep 5
    fi
  done

  echo "=== 최종 복제 상태 ==="
  mysql --defaults-file="/tmp/az_mycnf" \
    -h "$AZ_MYSQL_FQDN" --ssl-mode=REQUIRED -e \
    "SHOW SLAVE STATUS\G"
fi

echo "========================================"
echo "  DB 복제 완료 ✅"
echo "========================================"