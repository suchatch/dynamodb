#!/bin/bash
# setup-dynamodb-local.sh
# ตั้ง DynamoDB Local + สร้าง table + ใส่ข้อมูลตัวอย่าง (สำหรับทดลอง)
#
# ใช้: ./scripts/setup-dynamodb-local.sh
# ล้าง: ./scripts/cleanup-dynamodb-local.sh

set -e

EP="--endpoint-url http://localhost:8000 --region us-east-1"
CREDS_FILE="${HOME}/.aws-local-creds"
TABLE="shop"

# ── 1. credential (dummy — DynamoDB Local ไม่ตรวจ) ──
if [ ! -f "$CREDS_FILE" ]; then
  cat > "$CREDS_FILE" <<'EOF'
[default]
aws_access_key_id = dummy
aws_secret_access_key = dummy
EOF
  chmod 600 "$CREDS_FILE"
  echo "✓ สร้าง $CREDS_FILE (dummy)"
fi
export AWS_SHARED_CREDENTIALS_FILE="$CREDS_FILE"

# ── 2. start container ──
if docker ps -a --format '{{.Names}}' | grep -qx dynamodb-local; then
  docker start dynamodb-local >/dev/null
  echo "✓ start container เดิม"
else
  docker run -d --name dynamodb-local -p 8000:8000 \
    amazon/dynamodb-local:latest \
    -jar DynamoDBLocal.jar -inMemory -sharedDb >/dev/null
  echo "✓ สร้าง + start container"
fi

# รอให้พร้อม
for i in $(seq 1 20); do
  if aws dynamodb list-tables $EP >/dev/null 2>&1; then
    echo "✓ DynamoDB Local พร้อม (localhost:8000)"
    break
  fi
  sleep 1
done

# ── 3. สร้าง table (PK + SK) ──
if aws dynamodb describe-table $EP --table-name "$TABLE" >/dev/null 2>&1; then
  echo "✓ table '$TABLE' มีอยู่แล้ว"
else
  aws dynamodb create-table $EP \
    --table-name "$TABLE" \
    --attribute-definitions \
      AttributeName=PK,AttributeType=S \
      AttributeName=SK,AttributeType=S \
    --key-schema \
      AttributeName=PK,KeyType=HASH \
      AttributeName=SK,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST >/dev/null
  echo "✓ สร้าง table '$TABLE'"
fi

# ── 4. ใส่ข้อมูลตัวอย่าง ──
put() { aws dynamodb put-item $EP --table-name "$TABLE" --item "$1" >/dev/null; }

put '{"PK":{"S":"CUST#u001"},"SK":{"S":"PROFILE"},"name":{"S":"Somchai"},"email":{"S":"user@example.com"},"balance":{"N":"45900"}}'
put '{"PK":{"S":"CUST#u001"},"SK":{"S":"ORDER#2026-10-01"},"total":{"N":"450"},"status":{"S":"shipped"}}'
put '{"PK":{"S":"CUST#u001"},"SK":{"S":"ORDER#2026-10-05"},"total":{"N":"1200"},"status":{"S":"pending"}}'
put '{"PK":{"S":"CUST#u001"},"SK":{"S":"ORDER#2026-10-12"},"total":{"N":"300"},"status":{"S":"pending"}}'
put '{"PK":{"S":"CUST#u002"},"SK":{"S":"PROFILE"},"name":{"S":"Alice"}}'
put '{"PK":{"S":"CUST#u002"},"SK":{"S":"ORDER#2026-10-03"},"total":{"N":"890"},"status":{"S":"shipped"}}'
echo "✓ ใส่ข้อมูล 6 items"

# ── 5. GSI status-index ──
if aws dynamodb describe-table $EP --table-name "$TABLE" \
     --query 'Table.GlobalSecondaryIndexes[?IndexName==`status-index`]' \
     --output text 2>/dev/null | grep -q status-index; then
  echo "✓ GSI 'status-index' มีอยู่แล้ว"
else
  aws dynamodb update-table $EP --table-name "$TABLE" \
    --attribute-definitions AttributeName=status,AttributeType=S \
    --global-secondary-index-updates \
      '[{"Create":{"IndexName":"status-index","KeySchema":[{"AttributeName":"status","KeyType":"HASH"}],"Projection":{"ProjectionType":"ALL"}}}]' >/dev/null
  echo "✓ สร้าง GSI 'status-index' (รอ ACTIVE ~5 วิ)"
fi

# ── 6. summary ──
echo ""
echo "── สรุป ──"
aws dynamodb describe-table $EP --table-name "$TABLE" \
  --query 'Table.{Table:TableName,Items:ItemCount,Status:TableStatus,GSI:GlobalSecondaryIndexes[].IndexName}'
echo ""
echo "พร้อมทดลอง! ดูคำสั่งใน dynamodb-local-setup.md"
echo "  source: export AWS_SHARED_CREDENTIALS_FILE=$CREDS_FILE"
echo "  shortcut: export DDB=\"$EP\""
