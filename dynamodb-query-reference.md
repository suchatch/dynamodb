# DynamoDB Query & Operations — Reference

> API ทั้งหมด + ตัวอย่างจริง + 🔴 สิ่งที่ทำให้แพง/ช้า
> เทียบกับ SQL ทุกหัวข้อ
> ตัวอย่าง generic (e-commerce)

---

# 1. API หลัก — แบ่งเป็น 4 กลุ่ม

```
อ่าน:
  GetItem   → 1 item (เร็วสุด)
  Query     → หลาย item (ใช้ key) ★
  Scan      → ทั้ง table (❌ เลี่ยง)

เขียน:
  PutItem      → เพิ่ม/แทนที่ item
  UpdateItem   → แก้บาง attribute
  DeleteItem   → ลบ item
  BatchWriteItem → เขียนทีละ 25 item

หลาย operations:
  TransactWriteItems → หลาย operation แบบ atomic (≤ 100)
  BatchGetItem       → อ่านทีละ 100 item
```

---

# 2. อ่านข้อมูล

## 2.1 GetItem — ดึง item เดียว

```bash
aws dynamodb get-item \
  --table-name shop \
  --key '{"PK":{"S":"USER#u001"},"SK":{"S":"PROFILE"}}' \
  --consistent-read
```

```
✓ เร็วสุด (รู้ key ตรงๆ)
✓ strong consistency ได้ (--consistent-read, จ่าย 2x)
✗ ต้องรู้ key ทั้งหมด

เทียบ SQL: SELECT * FROM shop WHERE PK='USER#u001' AND SK='PROFILE' LIMIT 1
```

## 2.2 Query — ★ ใช้วิธีนี้

```bash
aws dynamodb query \
  --table-name shop \
  --key-condition-expression "PK = :pk AND SK BETWEEN :d1 AND :d2" \
  --expression-attribute-values '{
    ":pk":{"S":"USER#u001"},
    ":d1":{"S":"ORDER#2026-10-01"},
    ":d2":{"S":"ORDER#2026-10-31"}
  }' \
  --scan-index-forward false \
  --limit 20
```

**ส่วนประกอบ:**
```
KeyConditionExpression   ← ★ ต้องใช้ key (PK บังคับ, SK ได้)
FilterExpression         ← กรองหลังอ่าน (⚠️ จ่ายเท่าเดิม)
ProjectionExpression     ← เลือก field (ลดขนาด)
ScanIndexForward         ← true=เก่า→ใหม่, false=ใหม่→เก่า
Limit                    ← จำนวน item สูงสุด
ExclusiveStartKey        ← หน้าถัดไป (cursor)
```

**เทียบ SQL:**
```sql
SELECT ... FROM shop
WHERE PK = 'USER#u001'
  AND SK BETWEEN 'ORDER#2026-10-01' AND 'ORDER#2026-10-31'
ORDER BY SK DESC
LIMIT 20;
```

**★ Query ต้องมี KeyConditionExpression:**
```
✓ "PK = :pk"                          → ok
✓ "PK = :pk AND SK = :sk"             → ok
✓ "PK = :pk AND SK > :val"            → ok
✓ "PK = :pk AND begins_with(SK, :p)"  → ok
✗ "SK = :sk"                          → ✗ error! (ต้องมี PK)
✗ "PK = :pk AND name = :n"            → ✗ (name ไม่ใช่ key)
   → ต้องใช้ FilterExpression หรือ GSI
```

## 2.3 Scan — ❌ เลี่ยง

```bash
aws dynamodb scan \
  --table-name shop \
  --filter-expression "status = :s" \
  --expression-attribute-values '{":s":{"S":"pending"}}'
```

```
✗ อ่านทั้ง table แล้วกรอง
✗ จ่าย RCU ตามข้อมูลที่อ่าน "ทั้งหมด"
✗ ช้าถ้าข้อมูลเยอะ

เทียบ SQL: full table scan (ไม่มี index)
```

## 2.4 ★ ตารางเทียบ + ค่าใช้จ่าย

| | ใช้ key | อ่านเท่าไหร่ | ราคา | ใช้เมื่อ |
|---|---|---|---|---|
| GetItem | ✅ key ตรง | 1 item | 🟢 ต่ำสุด | ดึง item เดียว |
| Query | ✅ key | เฉพาะที่ match | 🟢 ต่ำ | ดึงหลาย item ตาม key |
| Query + Filter | ✅ key | ★ ตาม key (ไม่ใช่ตาม filter) | 🟡 | กรองเพิ่ม (ระวัง) |
| Scan | ❌ | ★ ทั้ง table | 🔴 สูง | ❌ เลี่ยง |

**★ ตัวอย่างราคา:**
```
Table 1,000,000 items (1 item = 1 KB)

Query หา user_id=u001 (มี 20 items):
  → อ่าน 20 items = 20 RCU/8KB-unit ≈ 3 RCU

Scan หา status=pending (มี 100 items):
  → ★ อ่าน 1,000,000 items! ≈ 125,000 RCU
  → แพงกว่า Query 40,000 เท่า!
```

## 2.5 Pagination

```
ทุก operation คืน ≤ 1 MB ต่อครั้ง (หรือ ≤ Limit)

ถ้ามีต่อ → คืน LastEvaluatedKey (cursor)
→ ใส่เป็น ExclusiveStartKey ในครั้งถัดไป
```

```bash
# ครั้งแรก
aws dynamodb query --table-name shop \
  --key-condition-expression "PK = :pk" \
  --expression-attribute-values '{":pk":{"S":"USER#u001"}}'
# → ได้ LastEvaluatedKey

# ครั้งถัดไป
aws dynamodb query --table-name shop \
  --key-condition-expression "PK = :pk" \
  --expression-attribute-values '{":pk":{"S":"USER#u001"}}' \
  --exclusive-start-key '{"PK":{"S":"USER#u001"},"SK":{"S":"ORDER#2026-10-20"}}'
```

**เทียบ SQL:** `LIMIT 20 OFFSET 20` (แต่ DynamoDB เร็วกว่า — cursor ไม่ต้องข้ามจริง)

**★ กับดัก:**
```
Limit ≠ จำนวนที่ได้เสมอ!

Query: Limit=20 + FilterExpression
  → อ่าน 20 items → filter → อาจได้ 3 items
  → ★ ยังจ่าย RCU ตาม 20 items ที่อ่าน
  → ต้อง query ต่อ (pagination) จนกว่าจะได้ครบ

เทียบ MySQL: WHERE ... LIMIT 20 → มักได้ 20 rows
```

---

# 3. เขียนข้อมูล

## 3.1 PutItem — เพิ่ม/แทนที่

```bash
aws dynamodb put-item \
  --table-name shop \
  --item '{
    "PK": {"S": "USER#u001"},
    "SK": {"S": "PROFILE"},
    "name": {"S": "Somchai"},
    "age": {"N": "32"}
  }'
```

**⚠️ PutItem = แทนที่ทั้ง item!**
```
ถ้า item มีอยู่ → ข้อมูลเดิมหายหมด (แทนด้วยของใหม่)
ถ้าไม่มี → สร้างใหม่

เทียบ SQL:
  PutItem          = REPLACE INTO (ลบเก่า + ใส่ใหม่)
  ★ ถ้าอยาก merge → ใช้ UpdateItem
```

## 3.2 UpdateItem — แก้บาง attribute ★

```bash
# แก้ค่า
aws dynamodb update-item --table-name shop \
  --key '{"PK":{"S":"USER#u001"},"SK":{"S":"PROFILE"}}' \
  --update-expression "SET #n = :name, age = :a" \
  --expression-attribute-names '{"#n":"name"}' \
  --expression-attribute-values '{":name":{"S":"Somchai J"},":a":{"N":"33"}}'

# เพิ่มค่าตัวเลข (atomic — ไม่ต้องอ่านก่อน)
--update-expression "SET balance = balance + :amt"

# เพิ่มใน set
--update-expression "ADD roles :r" \
--expression-attribute-values '{":r":{"SS":["premium"]}}'

# ลบออกจาก set
--update-expression "DELETE roles :r"

# ลบ attribute
--update-expression "REMOVE deleted_at"

# เขียนเมื่อเงื่อนไขผ่าน (conditional)
--update-expression "SET stock = stock - :one" \
--condition-expression "stock >= :one"
```

**เทียบ SQL:**
```sql
-- DynamoDB: SET balance = balance + :amt  ≈ MySQL: UPDATE SET balance = balance + 5
✅ atomic ไม่ต้อง lock
✗ ไม่มี JOIN / subquery
```

**★ Operations ใน UpdateExpression:**
| | ทำอะไร |
|---|---|
| `SET` | ตั้งค่า (หรือลบถ้าไม่มีค่า) |
| `REMOVE` | ลบ attribute |
| `ADD` | เพิ่มค่าจำนวน / เพิ่มใน set ★ |
| `DELETE` | ลบออกจาก set |

## 3.3 DeleteItem — ลบ

```bash
aws dynamodb delete-item --table-name shop \
  --key '{"PK":{"S":"USER#u001"},"SK":{"S":"PROFILE"}}'

# ลบเมื่อเงื่อนไขผ่าน
--condition-expression "attribute_exists(PK) AND #s = :s"
```

**เทียบ SQL:** `DELETE FROM shop WHERE PK=... AND SK=...`

**★ DeleteItem "สำเร็จ" แม้ item ไม่มี:**
```
ไม่มี item → คืน 200 OK (ไม่ error)
→ ถ้าต้องการ error → ใช้ ConditionExpression
   ConditionExpression: "attribute_exists(PK)"
```

## 3.4 BatchWriteItem — เขียนทีละ 25

```bash
aws dynamodb batch-write-item --request-items '{
  "shop": [
    {"PutRequest": {"Item": {"PK":{"S":"USER#u002"},"SK":{"S":"PROFILE"},"name":{"S":"Alice"}}}},
    {"PutRequest": {"Item": {"PK":{"S":"USER#u003"},"SK":{"S":"PROFILE"},"name":{"S":"Bob"}}}},
    {"DeleteRequest": {"Key": {"PK":{"S":"USER#u004"},"SK":{"S":"PROFILE"}}}}
  ]
}'
```

```
✓ 25 requests ต่อครั้ง
✓ เร็ว (ลด round trips)
✗ ไม่ atomic (บางอันสำเร็จ บางอันล้มได้)
✗ ไม่มี condition
```

**เทียบ SQL:** multi-row INSERT/DELETE (แต่เป็น batch ไม่ atomic)

## 3.5 BatchGetItem — อ่านทีละ 100

```bash
aws dynamodb batch-get-item --request-items '{
  "shop": {
    "Keys": [
      {"PK":{"S":"USER#u001"},"SK":{"S":"PROFILE"}},
      {"PK":{"S":"USER#u002"},"SK":{"S":"PROFILE"}}
    ],
    "ProjectionExpression": "name, email"
  }
}'
```

```
✓ 100 items ต่อครั้ง (หรือ 16 MB)
✓ ลด round trips
✗ บาง key อาจไม่เจอ (คืน UnprocessedKeys)
```

## 3.6 TransactWriteItems — atomic หลาย operation ★

```bash
aws dynamodb transact-write-items --transact-items '[
  {
    "Update": {
      "TableName": "shop",
      "Key": {"PK":{"S":"ACCOUNT#a1"},"SK":{"S":"BALANCE"}},
      "UpdateExpression": "SET balance = balance - :amt",
      "ConditionExpression": "balance >= :amt",
      "ExpressionAttributeValues": {":amt":{"N":"1000"}}
    }
  },
  {
    "Update": {
      "TableName": "shop",
      "Key": {"PK":{"S":"ACCOUNT#a2"},"SK":{"S":"BALANCE"}},
      "UpdateExpression": "SET balance = balance + :amt",
      "ExpressionAttributeValues": {":amt":{"N":"1000"}}
    }
  },
  {
    "Put": {
      "TableName": "shop",
      "Item": {
        "PK": {"S":"TX#t001"},
        "SK": {"S":"TRANSFER"},
        "amount": {"N":"1000"},
        "ts": {"S":"2026-10-13T10:00:00Z"}
      }
    }
  }
]'
```

```
✓ ทั้งหมดสำเร็จหรือล้มพร้อมกัน (atomic) ★
✓ เหมือน transaction ใน SQL
✗ จำกัด 100 operations ต่อครั้ง
✗ ช้ากว่า operation เดี่ยว (~2x)
✗ ไม่มี isolation level แบบ SQL (เป็น serializable)
```

**เทียบ SQL:**
```sql
BEGIN;
  UPDATE accounts SET balance = balance - 1000 WHERE id='a1' AND balance >= 1000;
  UPDATE accounts SET balance = balance + 1000 WHERE id='a2';
  INSERT INTO transfers ...;
COMMIT;
```

---

# 4. Expression — ไวยากรณ์ที่ต้องรู้

## 4.1 KeyConditionExpression (ใน Query)

```
ใช้ได้กับ key เท่านั้น:

"PK = :pk"
"PK = :pk AND SK = :sk"
"PK = :pk AND SK > :v"
"PK = :pk AND SK BETWEEN :a AND :b"
"PK = :pk AND begins_with(SK, :p)"

★ operators: =, <, <=, >, >=, BETWEEN, begins_with
✗ ห้ามใช้: <>, !=, OR, NOT, contains, in
```

## 4.2 FilterExpression (กรองเพิ่ม)

```
ใช้ได้กับ attribute ใดก็ได้ แต่ ★ กรอง "หลัง" อ่าน

"status = :s"
"price BETWEEN :min AND :max"
"attribute_exists(email)"
"attribute_not_exists(deleted_at)"
"contains(tags, :t)"
"begins_with(name, :p)"
"#a > :v AND #b < :w"

★ operator: =, <>, <, <=, >, >=, IN, BETWEEN, 
            attribute_exists, attribute_not_exists,
            contains, begins_with, AND, OR, NOT
```

**⚠️★ FilterExpression ไม่ลด RCU:**
```
Query PK="user#u001" (100 items) 
  + FilterExpression "age > 30" → เหลือ 5 items

จ่าย RCU: ตาม 100 items (ไม่ใช่ 5!)

→ ถ้ากรองบ่อย/กรองเยอะ → สร้าง GSI ที่รวมเงื่อนไขนั้นใน key
```

## 4.3 ProjectionExpression (เลือก field)

```
"name, email, age"
"#n, #e"
"address.city"          ← nested

★ ลดขนาดข้อมูลที่ส่ง → ลด RCU (ถ้า item ใหญ่)
```

## 4.4 UpdateExpression

```
"SET #n = :v"
"SET balance = balance + :amt"
"SET #c = if_not_exists(#c, :start)"      ← ตั้งถ้ายังไม่มี
"SET #l = list_append(#l, :item)"          ← ต่อ list
"REMOVE deleted_at"
"ADD roles :r"                             ← set/จำนวน
"DELETE roles :r"                          ← set
"SET a = :v1, b = :v2 REMOVE c ADD d :s"   ← หลาย op ในคำสั่งเดียว
```

## 4.5 ConditionExpression

```
ใช้กับ PutItem/UpdateItem/DeleteItem:

"attribute_not_exists(PK)"              ← สร้างใหม่เท่านั้น
"attribute_exists(PK)"                  ← update เท่านั้น
"#v = :expected"                        ← optimistic lock
"stock >= :one"                          ← เงื่อนไขธุรกิจ
"balance >= :amt"                        ← ยอดพอ
```

**★ ใช้ทำ optimistic locking:**
```
1. อ่าน item → ได้ version = 5
2. Update: SET ..., version = 6
   ConditionExpression: "version = :v" (v=5)
3. ถ้ามีคนอื่นแก้ไปแล้ว → version != 5 → error
   → อ่านใหม่ + ลองอีกครั้ง

เทียบ MySQL: SELECT ... FOR UPDATE ( pessimistic )
            หรือ version column (optimistic)
```

## 4.6 Attribute Names / Values

```
⚠️ ชื่อ attribute ที่เป็น reserved word (name, status, size...)
   → ใช้ ExpressionAttributeNames

--expression-attribute-names '{"#n":"name"}' \
--update-expression "SET #n = :v"

⚠️ ค่าที่ใส่ใน expression → ต้องใช้ ExpressionAttributeValues (ไม่ใส่ตรงๆ)

--expression-attribute-values '{":v":{"S":"Somchai"}}' \
--update-expression "SET name = :v"

★ ข้อดี: กัน injection + ใช้ค่าเดิมซ้ำได้
```

---

# 5. 🔴 สิ่งที่ทำให้แพง/ช้า — ห้ามทำบน prod

> ⚠️ DynamoDB คิดเงินตามข้อมูลที่ "อ่าน" → scan/query กว้าง = แพงทันที

## 5.1 🔴🔴 อันตราย — แพงมหาศาล

### ① Scan ทั้ง table บ่อยๆ

```bash
aws dynamodb scan --table-name big-table
```
```
Table 10M items (1 KB):
  → อ่าน 10,000,000 items = 1,250,000 RCU
  → On-demand: 1.25M × $0.25/1M = ★ $0.31 ต่อ scan 1 ครั้ง!
  → scan ทุก 5 นาที = $89/วัน = $2,670/เดือน!!

❌ ห้าม scan table ใหญ่เป็นประจำ
✅ ใช้ Query + GSI แทน
```

### ② Scan + Filter กลับ Filter เยอะ

```bash
aws dynamodb scan --table-name big-table \
  --filter-expression "status = :s AND type = :t"
```
```
★ Filter ไม่ลด RCU!
  Scan 10M → จ่าย 10M (แม้ได้ผล 100 items)

เทียบ: MySQL WHERE ที่ไม่ใช้ index → full scan + filter
✅ ออกแบบ GSI ที่มี status/type อยู่ใน key
```

### ③ Parallel Scan โดยไม่ระวัง

```bash
aws dynamodb scan --table-name big-table \
  --total-segments 10 --segment 0
```
```
ถ้าใช้ 10 segments → อ่านทั้ง table 10 เท่า concurrently
→ เร็วกว่า แต่จ่ายเท่าเดิมทั้งหมด + กระทบ throughput
❌ ไม่ควรใช้บน table ที่ traffic อื่นใช้อยู่
```

### ④ Query ที่ได้ผลเยอะมากๆ โดยไม่ Limit

```bash
aws dynamodb query --table-name big-table \
  --key-condition-expression "PK = :pk" \
  --expression-attribute-values '{":pk":{"S":"HOT_PARTITION"}}'
```
```
ถ้า PK = hot partition (มี 1M items):
  → อ่าน 1M items ต่อครั้ง = 125,000 RCU

✅ ใส่ Limit + pagination
✅ ออกแบบ PK ให้กระจาย (ไม่ให้มี > ~10k items ต่อ partition)
```

### ⑤ GSI ที่ทำให้โปรเจกต์อ่านแพง

```
GSI คิด RCU/WCU แยกจาก table
→ ทุก write → เขียนทั้ง table + GSI
→ ทุก query GSI → จ่าย + จ่าย
★ ถ้ามี 5 GSI → write 1 ครั้ง = จ่าย 6 เท่า

✅ ใช้ GSI เท่าที่จำเป็น (2-3 ตัวมักพอ)
```

## 5.2 🔴 ระวัง — กระทบ throughput

| การกระทำ | ปัญหา | ใช้แทน |
|---|---|---|
| Scan table ใหญ่ | อ่านทั้ง table | Query + GSI |
| Filter หลัง Scan | ไม่ลด RCU | GSI |
| Query hot partition | อ่านเยอะ | กระจาย PK |
| GSI หลายตัว | write แพง | เท่าที่จำเป็น |
| BatchGet 100 item ใหญ่ | กิน throughput | จำกัดขนาด |
| TransactWrite บ่อย | ช้า + แพง 2x | รวม/แยกถ้าได้ |
| Consistent read ทุก query | จ่าย 2x | ใช้ eventual ถ้าได้ |
| Item ใหญ่ (ใกล้ 400 KB) | กิน RCU มาก | เก็บไฟล์ที่ S3 |

## 5.3 ⚠️ ระดับความเสี่ยง

```
🟢 ปลอดภัย:
  GetItem (key ตรง)
  Query + Limit (PK เดียว, ไม่ hot)
  UpdateItem เดี่ยว
  BatchWrite 25

🟡 ระวัง:
  Query + Filter (จ่ายตามที่อ่าน)
  Query หลายหน้า
  BatchGet 100
  Consistent read

🔴 อันตราย:
  Scan table กลาง-ใหญ่
  Scan + Filter เยอะ
  Query hot partition (ไม่มี limit)
  Parallel scan บน prod

🔴🔴 อันตรายมาก:
  Scan table ใหญ่เป็นประจำ
  Scan ทุก 5 นาที (background job)
  GSI 5+ ตัว (write แพง)
  Item ใหญ่ + query เยอะ
```

## 5.4 ★ Checklist ก่อนยิง operation บน prod

```
[ ] 1. ใช้ key ไหม? (Query/GetItem — ไม่ใช่ Scan)
[ ] 2. ใส่ Limit เสมอ (Query/Scan)
[ ] 3. ระวัง hot partition (PK มี item เยอะไหม)
[ ] 4. Projection เลือก field ที่ต้องใช้
[ ] 5. ใช้ consistent read เท่าที่จำเป็น (จ่าย 2x)
[ ] 6. Filter ≠ ลดราคา — ถ้ากรองบ่อย → GSI
[ ] 7. ดู capacity ก่อน: ProvisionedThroughputExceeded ไหม
[ ] 8. ดู consumed capacity: --return-consumed-capacity TOTAL
[ ] 9. ทดสอบบน table เล็ก/table ทดสอบก่อน
[ ] 10. ตั้ง CloudWatch alarm: ConsumedReadCapacityUnits
```

## 5.5 ★ ตรวจว่าจ่ายไปเท่าไหร่ (สำคัญ!)

```bash
aws dynamodb query --table-name shop \
  --key-condition-expression "PK = :pk" \
  --expression-attribute-values '{":pk":{"S":"USER#u001"}}' \
  --return-consumed-capacity TOTAL

# ผลลัพธ์:
# {
#   "Count": 20,
#   "ScannedCount": 20,          ← ★ จำนวนที่อ่านจริง
#   "ConsumedCapacity": {
#     "TableName": "shop",
#     "CapacityUnits": 3.0        ← ★ RCU ที่ใช้
#   }
# }

★ ถ้า ScannedCount >> Count → filter ตัดออกเยอะ (จ่ายเกิน)
```

**เทียบ MySQL:**
```sql
EXPLAIN ANALYZE SELECT ...;
-- ดู rows examined vs rows returned
-- ★ เหมือนกัน: ถ้า examined >> returned = ไม่ efficient
```

## 5.6 ตั้ง alarm (CloudWatch)

```
Metrics ที่ควร monitor:
  ConsumedReadCapacityUnits      ← ดูว่าใช้เท่าไหร่
  ConsumedWriteCapacityUnits
  ReadThrottleEvents             ← ★ ถ้า > 0 = โดน limit
  WriteThrottleEvents            ← ★
  SystemErrors
  UserErrors                     ← validation/condition error

Alarm:
  ThrottleEvents > 0
  ConsumedCapacity สูงผิดปกติ
  Latency สูงขึ้น
```

---

# 6. ถ้าต้องอ่านข้อมูลเยอะ (แบบปลอดภัย)

## 6.1 Pagination + Limit

```bash
# อ่านทีละหน้า ไม่ดึงทั้งหมด
aws dynamodb query --limit 100 ... 
# → ใช้ LastEvaluatedKey ต่อ
```

## 6.2 ProjectionExpression — ลดขนาด

```bash
--projection-expression "PK, name"      # ไม่ดึง attribute ใหญ่
```

## 6.3 Parallel Scan (table ทดสอบเท่านั้น)

```bash
# ใช้เฉพาะ table ที่ traffic ไม่แย่ง / maintenance window
aws dynamodb scan --total-segments 4 --segment 0 &
aws dynamodb scan --total-segments 4 --segment 1 &
...
```

## 6.4 Export to S3 (ถ้าต้องวิเคราะห์)

```bash
# DynamoDB → S3 (ไม่กิน RCU! ใช้เวลา ไม่กิน throughput)
aws dynamodb export-table-to-point-in-time \
  --table-arn arn:aws:dynamodb:... \
  --s3-bucket my-bucket \
  --s3-prefix export/

# แล้วใช้ Athena query จาก S3
```
**★ วิธีนี้ไม่กิน RCU** — เหมาะกับ analytics

## 6.5 DAX (cache)

```
DynamoDB Accelerator = in-memory cache หน้า DynamoDB
→ ลด read latency (ms → µs)
→ ลด RCU (อ่านซ้ำๆ จาก cache)
→ ✅ เหมาะกับ read-heavy

⚠️ เสียเงินเพิ่ม + cache invalidation
```

## 6.6 TTL — ลบข้อมูลอัตโนมัติ

```bash
# ตั้ง TTL attribute (epoch seconds)
aws dynamodb update-time-to-live --table-name shop \
  --time-to-live-specification "Enabled=true,AttributeName=expire_at"

# item จะถูกลบอัตโนมัติเมื่อ expire_at ผ่าน
# ★ ไม่คิด WCU สำหรับการลบ (ฟรี)
```

---

# 7. ตารางเทียบ SQL → DynamoDB

| SQL | DynamoDB |
|---|---|
| `SELECT * WHERE pk=x LIMIT 1` | GetItem |
| `SELECT * WHERE pk=x AND sk>y` | Query |
| `SELECT * WHERE pk=x` | Query |
| `SELECT * WHERE other=z` | ★ ต้อง GSI หรือ Scan |
| `SELECT *` (ทั้ง table) | Scan ❌ |
| `INSERT` | PutItem |
| `REPLACE INTO` | PutItem (แทนที่ทั้ง item) |
| `UPDATE SET a=1` | UpdateItem `SET a=:v` |
| `UPDATE SET a=a+1` | UpdateItem `SET a = a + :v` |
| `UPDATE WHERE cond` | UpdateItem + ConditionExpression |
| `DELETE` | DeleteItem |
| `DELETE WHERE cond` | DeleteItem + ConditionExpression |
| `BEGIN...COMMIT` | TransactWriteItems |
| `COUNT(*)` | ⚠️ Scan + Count (แพง) |
| `GROUP BY` | ❌ (pre-aggregate) |
| `JOIN` | ❌ (denormalize) |
| `ORDER BY` | Sort Key (desc = ScanIndexForward false) |
| `LIMIT/OFFSET` | Limit + ExclusiveStartKey |
| `EXPLAIN` | `--return-consumed-capacity TOTAL` |

---

# 8. คำสั่งที่ใช้บ่อย (copy-paste)

```bash
# ดู table
aws dynamodb list-tables
aws dynamodb describe-table --table-name shop

# อ่าน
aws dynamodb get-item --table-name shop --key '{"PK":{"S":"USER#u001"},"SK":{"S":"PROFILE"}}'
aws dynamodb query --table-name shop \
  --key-condition-expression "PK = :pk" \
  --expression-attribute-values '{":pk":{"S":"USER#u001"}}' \
  --limit 10 --return-consumed-capacity TOTAL

# เขียน
aws dynamodb put-item --table-name shop --item '{"PK":{"S":"USER#u002"},"SK":{"S":"PROFILE"}}'
aws dynamodb update-item --table-name shop \
  --key '{"PK":{"S":"USER#u001"},"SK":{"S":"PROFILE"}}' \
  --update-expression "SET #n = :v" \
  --expression-attribute-names '{"#n":"name"}' \
  --expression-attribute-values '{":v":{"S":"New Name"}}'
aws dynamodb delete-item --table-name shop --key '{"PK":{"S":"USER#u002"},"SK":{"S":"PROFILE"}}'

# ดู capacity/ราคา
aws dynamodb describe-table --table-name shop \
  --query 'Table.{RCU:ProvisionedThroughput.ReadCapacityUnits,WCU:ProvisionedThroughput.WriteCapacityUnits}'

# ดู GSI
aws dynamodb describe-table --table-name shop \
  --query 'Table.GlobalSecondaryIndexes[].IndexName'
```

---

# สรุปสั้น

```

อ่าน:
  GetItem  → 1 item (เร็วสุด)
  Query    → ใช้ key ★ แนะนำ
  Scan     → ❌ เลี่ยง (อ่านทั้ง table = แพง)

เขียน:
  PutItem      → แทนที่ทั้ง item
  UpdateItem   → แก้บาง attribute (atomic)
  DeleteItem   → ลบ
  BatchWrite   → 25/ครั้ง (ไม่ atomic)
  TransactWrite → atomic (≤100)

Expression:
  KeyCondition   → Query (ใช้ key เท่านั้น)
  Filter         → กรองหลังอ่าน ⚠️ ไม่ลด RCU
  Projection     → เลือก field
  Update         → SET/REMOVE/ADD/DELETE
  Condition      → optimistic lock

🔴 ห้ามบน prod:
  ✗ Scan table ใหญ่เป็นประจำ
  ✗ Scan + Filter เยอะ (จ่ายเท่าเดิม)
  ✗ Query hot partition ไม่มี limit
  ✗ GSI 5+ ตัว (write แพง)
  ✗ Item ใหญ่เกือบ 400 KB

★ ตรวจราคา: --return-consumed-capacity TOTAL
★ MySQL EXPLAIN ≈ ดู ScannedCount vs Count
★ ถ้าต้องวิเคราะห์เยอะ → Export to S3 + Athena (ไม่กิน RCU)
```

---

## ไฟล์ที่เกี่ยวข้อง

```
why-dynamodb.md              ← ทำไมต้องใช้
dynamodb-key-design.md       ← PK/SK/GSI/LSI
dynamodb-data-types.md       ← data types
```
