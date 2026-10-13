#!/bin/bash
# demo-query-vs-scan.sh
# สาธิต: Query vs Scan vs GSI Query (พิสูจน์ด้วย ScannedCount)
#
# ใช้: ./scripts/demo-query-vs-scan.sh
# ต้องรัน setup-dynamodb-local.sh ก่อน

set -e

EP="--endpoint-url http://localhost:8000 --region us-east-1"
TABLE="shop"

# ── หา credential file (2 ที่: project dir → home) ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
if [ -f "$PROJECT_DIR/.aws-local-creds" ]; then
  export AWS_SHARED_CREDENTIALS_FILE="$PROJECT_DIR/.aws-local-creds"
elif [ -f "${HOME}/.aws-local-creds" ]; then
  export AWS_SHARED_CREDENTIALS_FILE="${HOME}/.aws-local-creds"
else
  echo "⚠️  ไม่พบ .aws-local-creds — รัน ./scripts/setup-dynamodb-local.sh ก่อน"
  exit 1
fi

line() { printf '%s\n' "──────────────────────────────────────────────────────────"; }

line
echo "① GetItem — ดึง item เดียว (PK + SK ตรง)"
line
aws dynamodb get-item $EP --table-name "$TABLE" \
  --key '{"PK":{"S":"CUST#u001"},"SK":{"S":"PROFILE"}}' \
  --projection-expression "#n, balance" \
  --expression-attribute-names '{"#n":"name"}' \
  --return-consumed-capacity TOTAL \
  --query '{Item:Item,CU:ConsumedCapacity.CapacityUnits}' --output json

line
echo "② Query (ใช้ key) — ออเดอร์ทั้งหมดของ u001"
line
aws dynamodb query $EP --table-name "$TABLE" \
  --key-condition-expression "PK = :pk AND begins_with(SK, :p)" \
  --expression-attribute-values '{":pk":{"S":"CUST#u001"},":p":{"S":"ORDER#"}}' \
  --return-consumed-capacity TOTAL \
  --query '{Count:Count,Scanned:ScannedCount,CU:ConsumedCapacity.CapacityUnits}' --output json

line
echo "③ Query + Filter — พิสูจน์ว่า Filter ไม่ลดการอ่าน"
line
aws dynamodb query $EP --table-name "$TABLE" \
  --key-condition-expression "PK = :pk" \
  --filter-expression "#s = :s" \
  --expression-attribute-names '{"#s":"status"}' \
  --expression-attribute-values '{":pk":{"S":"CUST#u001"},":s":{"S":"pending"}}' \
  --return-consumed-capacity TOTAL \
  --query '{Count:Count,Scanned:ScannedCount}' --output json
line
echo "④ Scan + Filter — ❌ อ่านทั้ง table"
line
aws dynamodb scan $EP --table-name "$TABLE" \
  --filter-expression "#s = :s" \
  --expression-attribute-names '{"#s":"status"}' \
  --expression-attribute-values '{":s":{"S":"pending"}}' \
  --return-consumed-capacity TOTAL \
  --query '{Count:Count,Scanned:ScannedCount}' --output json

line
echo "⑤ GSI Query — ★ ดีสุด (อ่านแค่ที่ match)"
line
aws dynamodb query $EP --table-name "$TABLE" \
  --index-name status-index \
  --key-condition-expression "#s = :s" \
  --expression-attribute-names '{"#s":"status"}' \
  --expression-attribute-values '{":s":{"S":"pending"}}' \
  --return-consumed-capacity TOTAL \
  --query '{Count:Count,Scanned:ScannedCount}' --output json

line
echo "สรุป — หา status=pending (มี 2 items ใน 6)"
line
cat <<'EOF'
  ① GetItem                    → ดึง key เดียว (เร็วสุด)
  ② Query  (key)               → Scanned 3  (แค่ partition u001)
  ③ Query + Filter             → Scanned 4  ← ★ Filter ไม่ลด!
  ④ Scan  + Filter             → Scanned 6  ← ❌ อ่านทั้ง table
  ⑤ GSI Query                  → Scanned 2  ← ★ ดีสุด

เทียบ SQL:
  Query = WHERE pk = x               (ใช้ index)
  Scan  = full table scan            (ช้า + แพง)
  GSI   = CREATE INDEX + WHERE y = z
EOF
