#!/bin/bash
# cleanup-dynamodb-local.sh
# หยุด + ลบ DynamoDB Local (และ credential file)
#
# ใช้: ./scripts/cleanup-dynamodb-local.sh

set -e

echo "── Stopping DynamoDB Local ──"
docker rm -f dynamodb-local 2>/dev/null && echo "✓ ลบ container" || echo "  (ไม่มี container)"

echo "── ลบ volume (ถ้ามี) ──"
docker volume rm ddb-data 2>/dev/null && echo "✓ ลบ volume" || echo "  (ไม่มี volume)"

echo "── credential file ──"
read -r -p "ลบ ~/.aws-local-creds ด้วย? (y/N): " ans
if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
  rm -f "${HOME}/.aws-local-creds" && echo "✓ ลบแล้ว"
else
  echo "  เก็บไว้"
fi

echo ""
echo "✓ cleanup เสร็จ"
