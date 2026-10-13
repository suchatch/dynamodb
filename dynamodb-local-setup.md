# DynamoDB Local — Setup & ทดลอง

> รัน DynamoDB ในเครื่อง (ฟรี ไม่ต้องมี AWS account) เพื่อทดลองของจริง
> ใช้กับ repo นี้ (docs) — เป็น lab สำหรับฝึก

---

# 1. ทำไมต้อง DynamoDB Local

```
✓ ฟรี — ไม่ต้องมี AWS account / ไม่เสียเงิน
✓ เร็ว — ทดลองได้ทันที (ไม่ต้องรอ deploy)
✓ API เหมือนของจริง → โค้ดย้ายไป AWS ได้เลย
✓ ปลอดภัย — ข้อมูลอยู่ในเครื่อง ไม่มี packet ออก internet

⚠️ ต่างจากของจริง:
  ✗ ไม่มี IAM (credential ปลอมก็ได้)
  ✗ ไม่คิดเงิน (RCU/WCU ไม่จริง)
  ✗ ไม่มี CloudWatch / billing
  ✗ default = in-memory (ปิด container = ข้อมูลหาย)
```

**ใช้เมื่อ:** เรียน, ทดลอง key design, ทดสอบโค้ดก่อน deploy
**ไม่ใช้เมื่อ:** ต้องการ test performance จริง / capacity planning

---

# 2. Prerequisites

```
Docker (สำหรับรัน DynamoDB Local)
aws cli v2 (หรือ boto3)
```

เช็ค:
```bash
docker --version
aws --version
```

---

# 3. Setup

## 3.1 Start DynamoDB Local

```bash
docker run -d --name dynamodb-local -p 8000:8000 \
  amazon/dynamodb-local:latest \
  -jar DynamoDBLocal.jar -inMemory -sharedDb
```

**flag:**
```
-inMemory   เก็บข้อมูลใน RAM (หายเมื่อปิด container)
-sharedDb   ใช้ DB เดียวกันทุก credential (ทดสอบง่าย)
```

**ถ้าอยากเก็บข้อมูลถาวร** (หายเมื่อปิดเครื่อง — เก็บใน volume):
```bash
docker volume create ddb-data
docker run -d --name dynamodb-local -p 8000:8000 \
  -v ddb-data:/home/dynamodblocal/data \
  amazon/dynamodb-local:latest \
  -jar DynamoDBLocal.jar -sharedDb -dbPath /home/dynamodblocal/data
```

## 3.2 Credential (dummy)

```
⚠️ DynamoDB Local 3.x ยังต้อง auth
   → ใช้ credential ปลอม (ไม่ถูกส่งไปไหน)

★ วิธีสะอาด: ใช้ไฟล์ (ไม่ export ใน command)
```

สร้างไฟล์ `~/.aws-local-creds`:
```ini
[default]
aws_access_key_id = dummy
aws_secret_access_key = dummy
```

```bash
chmod 600 ~/.aws-local-creds
export AWS_SHARED_CREDENTIALS_FILE=~/.aws-local-creds
```

**★ ต้องเพิ่มใน .gitignore** (ถ้าอยู่ในโปรเจกต์):
```
.aws-local-creds
```

## 3.3 ตั้ง shortcut (ไม่ต้องพิมพ์ endpoint ทุกครั้ง)

```bash
export DDB="--endpoint-url http://localhost:8000 --region us-east-1"
```

---

# 4. ทดสอบว่าใช้ได้

```bash
aws dynamodb list-tables $DDB --output json
# → {"TableNames": []}   ← ว่าง = ทำงาน
```

---

# 5. ทดลอง — สร้าง table + ใส่ข้อมูล

## 5.1 สร้าง table (PK + SK)

```bash
aws dynamodb create-table $DDB \
  --table-name shop \
  --attribute-definitions \
    AttributeName=PK,AttributeType=S \
    AttributeName=SK,AttributeType=S \
  --key-schema \
    AttributeName=PK,KeyType=HASH \
    AttributeName=SK,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST
```

**เทียบ concept:**
```
--attribute-definitions = ประกาศ field ที่ใช้เป็น key
                          (field อื่นไม่ต้องประกาศ — schemaless)
--key-schema            = PK (HASH) + SK (RANGE)
--billing-mode          = PAY_PER_REQUEST (on-demand)
                          local ไม่คิดเงิน แต่ต้องระบุ
```

## 5.2 ใส่ข้อมูล

```bash
# user profile
aws dynamodb put-item $DDB --table-name shop --item '{
  "PK": {"S": "CUST#u001"}, "SK": {"S": "PROFILE"},
  "name": {"S": "Somchai"}, "email": {"S": "user@example.com"},
  "balance": {"N": "45900"}
}'

# orders ของ u001 (PK ซ้ำได้, SK ต่าง)
aws dynamodb put-item $DDB --table-name shop --item '{
  "PK": {"S": "CUST#u001"}, "SK": {"S": "ORDER#2026-10-01"},
  "total": {"N": "450"}, "status": {"S": "shipped"}
}'
aws dynamodb put-item $DDB --table-name shop --item '{
  "PK": {"S": "CUST#u001"}, "SK": {"S": "ORDER#2026-10-05"},
  "total": {"N": "1200"}, "status": {"S": "pending"}
}'
aws dynamodb put-item $DDB --table-name shop --item '{
  "PK": {"S": "CUST#u001"}, "SK": {"S": "ORDER#2026-10-12"},
  "total": {"N": "300"}, "status": {"S": "pending"}
}'
```

**★ สังเกต:** PK "CUST#u001" ซ้ำได้ (3 orders) — แต่ PK+SK ไม่ซ้ำ

---

# 6. ทดลอง — พิสูจน์ Query vs Scan

## 6.1 Query (ใช้ key) — เร็ว

```bash
aws dynamodb query $DDB --table-name shop \
  --key-condition-expression "PK = :pk AND begins_with(SK, :p)" \
  --expression-attribute-values '{":pk":{"S":"CUST#u001"},":p":{"S":"ORDER#"}}' \
  --return-consumed-capacity TOTAL \
  --query '{Count:Count,Scanned:ScannedCount,CU:ConsumedCapacity.CapacityUnits}'
# → Count 3, Scanned 3  ★ อ่านแค่ที่ match
```

## 6.2 Scan (อ่านทั้ง table) — ช้า

```bash
aws dynamodb scan $DDB --table-name shop \
  --filter-expression "#s = :s" \
  --expression-attribute-names '{"#s":"status"}' \
  --expression-attribute-values '{":s":{"S":"pending"}}' \
  --return-consumed-capacity TOTAL \
  --query '{Count:Count,Scanned:ScannedCount}'
# → Count 2, ★ Scanned 6  (อ่านทั้ง table!)
```

## 6.3 ★ Query + Filter — Filter ไม่ลดการอ่าน

```bash
aws dynamodb query $DDB --table-name shop \
  --key-condition-expression "PK = :pk" \
  --filter-expression "#s = :s" \
  --expression-attribute-names '{"#s":"status"}' \
  --expression-attribute-values '{":pk":{"S":"CUST#u001"},":s":{"S":"pending"}}' \
  --return-consumed-capacity TOTAL \
  --query '{Count:Count,Scanned:ScannedCount}'
# → Count 2, Scanned 4  ★ อ่านทั้ง partition (Filter กรองหลังอ่าน)
```

**★ บทเรียน (พิสูจน์ด้วยตัวเลข):**
```
หา status=pending (มี 2 items):
  Scan          → อ่าน 6 (ทั้ง table)
  Query+Filter  → อ่าน 4 (ทั้ง partition)  ← Filter ไม่ช่วย
  GSI Query     → อ่าน 2 (แค่ที่ match)     ★ ดีสุด (ดูข้อ 8)
```

---

# 7. ทดลอง — UpdateItem + ConditionExpression

## 7.1 Atomic increment

```bash
aws dynamodb update-item $DDB --table-name shop \
  --key '{"PK":{"S":"CUST#u001"},"SK":{"S":"PROFILE"}}' \
  --update-expression "SET balance = balance + :amt" \
  --expression-attribute-values '{":amt":{"N":"100"}}' \
  --return-values ALL_NEW \
  --query 'Attributes.balance.N'
# → 46000  (45900 + 100 — atomic ไม่ต้องอ่านก่อน)
```

**เทียบ SQL:** `UPDATE SET balance = balance + 100` (atomic เหมือนกัน)

## 7.2 ConditionExpression — ป้องกัน overwrite

```bash
aws dynamodb put-item $DDB --table-name shop \
  --item '{"PK":{"S":"CUST#u001"},"SK":{"S":"PROFILE"},"name":{"S":"HACKED"}}' \
  --condition-expression "attribute_not_exists(PK)"
# → ConditionalCheckFailedException ★ (item มีอยู่แล้ว)
```

**ยืนยัน:**
```bash
aws dynamodb get-item $DDB --table-name shop \
  --key '{"PK":{"S":"CUST#u001"},"SK":{"S":"PROFILE"}}' \
  --query 'Item.name.S'
# → "Somchai"  (ไม่ถูกแก้เป็น HACKED)
```

**เทียบ SQL:** `INSERT ... ON DUPLICATE KEY` / `UNIQUE constraint`

---

# 8. ทดลอง — GSI (query ด้วย field ที่ไม่ใช่ key)

## 8.1 ลองก่อน (ต้อง error)

```bash
aws dynamodb query $DDB --table-name shop \
  --key-condition-expression "#s = :s" \
  --expression-attribute-names '{"#s":"status"}' \
  --expression-attribute-values '{":s":{"S":"pending"}}'
# → ValidationException: "Query condition missed key schema element"
```

## 8.2 สร้าง GSI

```bash
aws dynamodb update-table $DDB --table-name shop \
  --attribute-definitions AttributeName=status,AttributeType=S \
  --global-secondary-index-updates \
    '[{"Create":{"IndexName":"status-index","KeySchema":[{"AttributeName":"status","KeyType":"HASH"}],"Projection":{"ProjectionType":"ALL"}}}]'
```

**รอ GSI ACTIVE** (~5 วิ):
```bash
aws dynamodb describe-table $DDB --table-name shop \
  --query 'Table.GlobalSecondaryIndexes[].{Name:IndexName,Status:IndexStatus}'
```

## 8.3 Query ผ่าน GSI

```bash
aws dynamodb query $DDB --table-name shop \
  --index-name status-index \
  --key-condition-expression "#s = :s" \
  --expression-attribute-names '{"#s":"status"}' \
  --expression-attribute-values '{":s":{"S":"pending"}}' \
  --return-consumed-capacity TOTAL \
  --query '{Count:Count,Scanned:ScannedCount}'
# → Count 2, Scanned 2  ★ อ่านแค่ที่ match (ข้ามทุก user)
```

**★ นี่คือสิ่งที่ Query ปกติทำไม่ได้** — query ด้วย field ที่ไม่ใช่ key

---

# 9. ★ กับดักที่เจอจริง

```
① DynamoDB Local 3.x ยังต้อง auth
   ✗ --no-sign-request ใช้ไม่ได้
   ✓ ใช้ credential file (dummy) — สะอาดกว่า export

② aws cli v2 boolean flag
   ✗ --scan-index-forward false   → error
   ✗ --scan-index-forward=false   → error
   ✓ --scan-index-forward         → true
   ✓ --no-scan-index-forward      → false ★

③ GSI สร้างไม่เสร็จทันที
   → status: CREATING → ACTIVE (~5 วิ)
   → ต้องรอ ก่อน query

④ Query ด้วย field ที่ไม่ใช่ key
   → ValidationException: "Query condition missed key schema element"
   → ต้องสร้าง GSI

⑤ DeletedItem "สำเร็จ" แม้ item ไม่มี
   → ไม่ error (คืน 200)
   → ถ้าต้องการ error: --condition-expression "attribute_exists(PK)"

⑥ PutItem = แทนที่ทั้ง item
   → ข้อมูลเดิมหาย! (ถ้าต้องการ merge → UpdateItem)

⑦ default = in-memory
   → docker stop/rm = ข้อมูลหายหมด
   → ถ้าอยากเก็บ → ใช้ -dbPath + volume
```

---

# 10. Cleanup

```bash
# หยุดชั่วคราว
docker stop dynamodb-local

# ลบทั้งหมด
docker rm -f dynamodb-local

# ลบ volume (ถ้าใช้ -dbPath)
docker volume rm ddb-data
```

---

# 11. ใช้ boto3 (Python) แทน CLI

```python
import boto3

dynamodb = boto3.resource(
    'dynamodb',
    endpoint_url='http://localhost:8000',
    region_name='us-east-1',
    aws_access_key_id='dummy',       # ★ ยังต้องมี (แต่ local ไม่ตรวจ)
    aws_secret_access_key='dummy',
)

table = dynamodb.Table('shop')

# GetItem
resp = table.get_item(Key={'PK': 'CUST#u001', 'SK': 'PROFILE'})
print(resp.get('Item'))

# Query
from boto3.dynamodb.conditions import Key
resp = table.query(
    KeyConditionExpression=Key('PK').eq('CUST#u001') & Key('SK').begins_with('ORDER#')
)
print(resp['Items'])

# UpdateItem (atomic)
table.update_item(
    Key={'PK': 'CUST#u001', 'SK': 'PROFILE'},
    UpdateExpression='SET balance = balance + :amt',
    ExpressionAttributeValues={':amt': 100},
)
```

**ติดตั้ง:** `pip install boto3` หรือ `uv pip install boto3`

---

# 12. NoSQL Workbench (GUI)

```
เครื่องมือออกแบบของ AWS (ฟรี):
  ✓ visual data modeler
  ✓ query testing
  ✓ ต่อ DynamoDB Local ได้

โหลด: https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/workbench.html
```

**ใช้ทำอะไร:**
```
① ออกแบบ table + GSI (เห็นภาพ)
② ทดสอบ access pattern (ก่อนเขียนโค้ด)
③ ดูว่า query ใช้ key ถูกไหม
```

---

# 13. Checklist การทดลอง

```
[ ] start DynamoDB Local (docker)
[ ] ตั้ง credential file (dummy) + gitignore
[ ] สร้าง table (PK + SK)
[ ] ใส่ข้อมูล (PK ซ้ำได้)
[ ] เปรียบ GetItem vs Query vs Scan
[ ] พิสูจน์ Filter ไม่ลดการอ่าน
[ ] UpdateItem (atomic increment)
[ ] ConditionExpression (ป้องกัน overwrite)
[ ] สร้าง GSI + query
[ ] เทียบ GSI Query vs Scan (ราคา)
[ ] ทดลอง boto3
[ ] cleanup
```

---

## ไฟล์ที่เกี่ยวข้อง

```
why-dynamodb.md               ทำไมต้อง DynamoDB
dynamodb-key-design.md        PK/SK/GSI/LSI
dynamodb-query-reference.md   API + ราคา
dynamodb-best-practices.md    แนวปฏิบัติที่ดี
scripts/                      script ที่รันได้ (ดูในโปรเจกต์)
```
