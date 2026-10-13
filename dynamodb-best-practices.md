# DynamoDB Best Practices — Reference

> แนวปฏิบัติที่ดี (จาก AWS docs + บทเรียนจริง)
> เขียนสำหรับคนสาย SQL/MongoDB — เน้นสิ่งที่ "ต่าง" จากที่เคยทำ
> ตัวอย่าง generic (e-commerce)

---

# ส่วนที่ 1: Key Design

## 1.1 ★ เริ่มจาก Access Patterns (ไม่ใช่จาก Entity)

```
❌ วิธีของคนสาย SQL:
   1. ดูว่ามี entity อะไร (user, order, product)
   2. สร้าง table ละ entity
   3. แล้วค่อยคิดว่าจะ query อะไร

✅ วิธีของ DynamoDB:
   1. ★ เขียน access pattern ทั้งหมดก่อน
      "ดู user ตาม id", "ดู order ของ user", "ดู order ตาม status"
   2. ออกแบบ key ให้ตอบ pattern เหล่านี้
   3. ตรวจว่าไม่มี pattern ไหนต้อง Scan
```

**เทียบ:**
```
MySQL:    schema-driven (เริ่มจากข้อมูล)
DynamoDB: query-driven (เริ่มจากคำถาม)
```

## 1.2 เลือก Partition Key ที่กระจายดี

```
❌ PK = status        → "active" 900k items → hot partition
❌ PK = category      → ค่าไม่กี่แบบ
❌ PK = date          → วันนี้ทุก write ไปวันเดียว
❌ PK = created_at    → เหมือน date

✅ PK = user_id       → กระจายดี
✅ PK = order_id      → กระจายสม่ำเสมอ (uuid)
✅ PK = tenant_id#date → ผสมเพื่อกระจาย
```

**★ เกณฑ์:**
```
✓ ค่าหลากหลาย (high cardinality)
✓ กระจายสม่ำเสมอ (uniform)
✓ เข้าถึงบ่อย (เป็น query หลัก)
```

## 1.3 Write Sharding (ถ้า PK จำเป็นต้องมีค่าไม่มาก)

```
ปัญหา: ต้อง partition ตาม date แต่ทุก write วันนี้ไป partition เดียว

แก้: PK = date#random(0..9)
  "2026-10-13#0" ... "2026-10-13#9"    → กระจาย 10 partition

Query: ต้อง query ทั้ง 10 แล้วรวมผล
  → เก็บ meta ว่าใช้ suffix อะไร (หรือ query ทั้งหมดแบบขนาน)
```

## 1.4 ใช้ Sort Key ให้เป็นประโยชน์

```
Sort Key ช่วย: เรียง / ช่วง / begins_with

SK = "date"                 → เรียงวันที่, query ช่วง
SK = "status#date"          → กรอง status + เรียงวันที่
SK = "type#id"              → แยก entity type

★ ลำดับใน composite key สำคัญ:
   "status#date"  → กรอง status ได้ (begins_with)
   "date#status"  → กรอง status ไม่ได้
```

## 1.5 Composite Key ที่มีความหมาย (semantic)

```
PK = "CUST#u001"      SK = "ORDER#2026-10-01"
PK = "CUST#u001"      SK = "PROFILE"

★ ข้อดี:
  - อ่านรู้เลยว่า entity อะไร (prefix)
  - หลาย entity ใน partition เดียว → query ทีเดียวได้
  - กระจายดี (prefix ต่างกัน)
```

---

# ส่วนที่ 2: Single-Table Design

## 2.1 หลักการ

```
★ 1 table เก็บหลาย entity (แทนที่จะ 1 table/entity)

ข้อดี:
  ✓ query หลาย entity ในคำสั่งเดียว (เพราะอยู่ใน partition เดียว)
  ✓ ลดจำนวน round trips
  ✓ จ่ายน้อยกว่า (query เดียว vs 3 query)

ข้อเสีย:
  ✗ ยาก (ต้องคิดแบบ DynamoDB)
  ✗ ทีมใหม่เข้าใจยาก / maintain ยาก
```

## 2.2 ตัวอย่าง

```
Table: app

Items:
  PK              SK                    Entity
  ──────────────  ────────────────────  ──────────
  CUST#u001       PROFILE               user
  CUST#u001       ORDER#2026-10-01      order
  CUST#u001       ORDER#2026-10-05      order
  CUST#u001       CART#current          cart
  CUST#u002       PROFILE               user
  PROD#p001       DETAIL                product
  PROD#p001       REVIEW#r001           review

★ Query PK="CUST#u001" → ได้ profile + orders + cart (คำสั่งเดียว!)
```

## 2.3 เมื่อไหร่ใช้ / ไม่ใช้

| ใช้ single-table เมื่อ | ใช้ multi-table เมื่อ |
|---|---|
| งานจริงจัง, performance สูง | ทีมใหม่ / งานเล็ก |
| entity สัมพันธ์กัน (query รวม) | entity แยกกันชัดเจน |
| ต้องการลด round trips | ต้องการความชัดเจน |
| ทีมเข้าใจ DynamoDB | maintain ง่ายกว่า |

**★ คำแนะนำ:** เริ่มจาก multi-table ก่อน → เรียนรู้ → ค่อยขยับเป็น single-table (ถ้าจำเป็น)

---

# ส่วนที่ 3: การอ่านข้อมูล

## 3.1 ใช้ Query ไม่ใช่ Scan

```
❌ Scan = อ่านทั้ง table → แพง
✅ Query = ใช้ key → ถูก + เร็ว
```

**ถ้าต้องการข้อมูลที่ key ไม่ตอบ:**
```
เพิ่ม GSI (เฉพาะที่จำเป็น)
หรือ denormalize (เก็บข้อมูลซ้ำเพื่อ query)
```

## 3.2 ★ ระวัง FilterExpression

```
★ Filter กรอง "หลัง" อ่าน — ไม่ลด RCU!

Query PK="u001" (100 items) + Filter "age>30" → เหลือ 5 items
→ จ่าย RCU ตาม 100 items (ไม่ใช่ 5)

★ ถ้ากรองบ่อย/เหลือน้อย → สร้าง GSI ที่รวมเงื่อนไขใน key
```

## 3.3 Pagination เสมอ

```
ทุก Query/Scan คืน ≤ 1 MB
→ ถ้ามีต่อ ใช้ LastEvaluatedKey

★ ใส่ Limit ให้เหมาะ (อย่าดึงเยอะ)
```

## 3.4 ProjectionExpression

```
เลือกเฉพาะ field ที่ใช้:
--projection-expression "PK, SK, name, price"

★ ลดขนาดข้อมูล → ลด RCU (ถ้า item ใหญ่)
```

## 3.5 Consistent Read — ใช้เท่าที่จำเป็น

```
ConsistentRead = true → จ่าย RCU 2 เท่า
แต่ได้ข้อมูลล่าสุดแน่นอน

★ ใช้เมื่อ: อ่านหลัง write ทันที (สำคัญ)
★ ไม่ใช้เมื่อ: eventual consistency ยอมรับได้ (ส่วนใหญ่)
```

## 3.6 ★ ตรวจราคาทุกครั้ง (ระหว่างพัฒนา)

```bash
--return-consumed-capacity TOTAL

★ ดู ScannedCount vs Count:
   ถ้า ScannedCount >> Count → filter ตัดออกเยอะ = inefficient
   
เทียบ MySQL: EXPLAIN ANALYZE (rows examined vs returned)
```

---

# ส่วนที่ 4: การเขียนข้อมูล

## 4.1 UpdateItem แทน PutItem

```
❌ PutItem → แทนที่ทั้ง item (ข้อมูลเดิมหาย)
✅ UpdateItem → แก้เฉพาะ field ที่ต้องการ

ใช้ PutItem เมื่อ:
  ✓ สร้าง item ใหม่
  ✓ ต้องการแทนที่ทั้ง item

ใช้ UpdateItem เมื่อ:
  ✓ แก้บาง field
  ✓ atomic increment (SET x = x + :v)
  ✓ เขียนเมื่อเงื่อนไขผ่าน (ConditionExpression)
```

## 4.2 ConditionExpression — ใช้ทุกครั้งที่สำคัญ

```bash
# สร้างใหม่เท่านั้น (กัน overwrite)
ConditionExpression: "attribute_not_exists(PK)"

# optimistic locking
ConditionExpression: "version = :v"

# เงื่อนไขธุรกิจ
ConditionExpression: "stock >= :one"
```

**เทียบ SQL:**
```sql
INSERT ... ON DUPLICATE KEY UPDATE   ≈ ConditionExpression
SELECT ... FOR UPDATE                ≈ version check (optimistic)
```

## 4.3 Atomic Counter

```bash
UpdateExpression: "SET views = views + :one"
# ★ atomic ไม่ต้องอ่านก่อน ไม่มี race
```

**เทียบ SQL:**
```sql
UPDATE SET views = views + 1;   -- MySQL ก็ atomic
```

## 4.4 BatchWrite — ระวัง

```
✓ 25 requests ต่อครั้ง (เร็ว)
✗ ไม่ atomic (บางอันสำเร็จ บางอันล้ม)
✗ ไม่มี condition
→ ถ้าต้อง atomic → ใช้ TransactWriteItems
```

## 4.5 TransactWriteItems — ใช้เมื่อจำเป็น

```
✓ atomic (ทั้งหมดสำเร็จหรือล้มพร้อมกัน)
✗ ≤ 100 operations
✗ ช้ากว่า ~2 เท่า
✗ ไม่มี condition บน GSI

★ ใช้เมื่อ: ต้อง atomic จริง (โอนเงิน, จองสต็อก)
★ ไม่ใช้เมื่อ: operation เดี่ยว (จ่ายแพงโดยไม่จำเป็น)
```

## 4.6 ★ Idempotency

```
ปัญหา: retry แล้วเขียนซ้ำ (network error → ลองใหม่ → 2 records)

แก้: ใช้ idempotency key
  PK = "REQ#<request-id>"
  ConditionExpression: "attribute_not_exists(PK)"
  
→ retry ด้วย request-id เดิม → ครั้งที่ 2 ล้มเงียบ (ไม่เขียนซ้ำ)
   แล้วคืนผลเดิม (ถ้าเก็บผลไว้)

เทียบ SQL: UNIQUE constraint บน idempotency key
```

---

# ส่วนที่ 5: การออกแบบ Item

## 5.1 ขนาด item ≤ 400 KB

```
⚠️ ขีดจำกัดแข็ง — เกิน = error

ถ้าใกล้ 400 KB:
  ✓ ย้ายไฟล์ใหญ่ไป S3 (เก็บ path)
  ✓ แยก item (1 item = 1 chunk)
  ✓ เก็บ summary ในหลัก detail ใน item แยก
```

## 5.2 อย่าใส่ attribute เยอะเกินจำเป็น

```
★ item ใหญ่ = กิน RCU/WCU มาก (คิดตามขนาด)

ถ้าไม่ค่อยใช้ field ใหญ่ → แยกไป item อื่น / S3
```

## 5.3 จำนวน attribute ต่อ item

```
ไม่มีการจำกัดจำนวน แต่:
  - item size จำกัด 400 KB (รวมทุก attribute)
  - attribute name กินพื้นที่ด้วย!
    {"userName": ...} กับ {"user_name_2": ...} → ยาวกว่า = กินมากกว่า

★ ใช้ชื่อ attribute สั้นๆ ในงานที่มี item เยอะ (ประหยัด)
```

## 5.4 เก็บ data ที่ query บ่อยไว้ที่ระดับบนสุด

```
❌ query บ่อยแต่ข้อมูลซ้อนลึก:
  {"order": {"customer": {"address": {"city": "Bangkok"}}}}
  → query/filter city ไม่ได้ (ไม่ใช่ key)

✅ denormalize ถ้าต้อง query:
  {"city": "Bangkok", "order": {...}}
```

---

# ส่วนที่ 6: Index (GSI/LSI)

## 6.1 GSI — ใช้เท่าที่จำเป็น

```
⚠️ GSI คิด RCU/WCU แยก
   write 1 ครั้ง → จ่ายทั้ง table + ทุก GSI
   
★ 5 GSI → write 1 ครั้ง = จ่าย 6 เท่า

★ ใช้ 2-3 ตัวมักพอ
```

## 6.2 GSI ต้องมี key ที่กระจายด้วย

```
GSI PK = status        → hot partition (เหมือน table)
GSI PK = status#date   → กระจายดีขึ้น
```

## 6.3 LSI — สร้างทีหลังไม่ได้

```
★ LSI เพิ่มได้เฉพาะตอน CreateTable

→ ถ้าต้องการ LSI: วางแผนตั้งแต่แรก
→ ถ้าลืม: migrate table ใหม่ (เจ็บ)
```

## 6.4 Projection ใน GSI

```
GSI มี 3 แบบ projection:
  KEYS_ONLY           → เก็บแค่ key (ประหยัด)
  INCLUDE             → key + field ที่ระบุ
  ALL                 → ทุกอย่าง (กินมากสุด)

★ KEYS_ONLY ประหยัดสุด แต่ต้อง fetch จาก table (เพิ่ม RCU)
★ INCLUDE = สมดุล (แนะนำ)
★ ALL = สะดวกแต่แพง
```

## 6.5 Index Overloading

```
เทคนิค: ใช้ GSI เดียว สำหรับหลาย query

GSI PK = "TYPE#<entity>#<field>"
  "TYPE#ORDER#pending"
  "TYPE#ORDER#shipped"

→ GSI เดียวรองรับ query หลายแบบ (ลดจำนวน GSI)
```

---

# ส่วนที่ 7: Capacity & Cost

## 7.1 เริ่มจาก On-Demand

```
On-Demand:
  ✓ ไม่ต้องตั้ง capacity (AWS ปรับให้)
  ✓ เหมาะกับ traffic ไม่แน่นอน
  ✗ แพงกว่า ~5-7 เท่า (ถ้า traffic สม่ำเสมอ)

Provisioned:
  ✓ ถูกกว่า (ถ้าตั้ง capacity ถูก)
  ✗ ถ้าเกิน → throttle

★ เริ่ม On-Demand → ดู traffic → ถ้าสม่ำเสมอค่อยเปลี่ยน
   (DynamoDB มี auto-switch ได้)
```

## 7.2 ★ Scan แพงมาก — หลีกเลี่ยง

```
Table 10M items:
  Query 20 items  → ~3 RCU
  Scan ทั้ง table → 1,250,000 RCU  ★ แพงกว่า 400,000 เท่า

★ background job ที่ scan = ค่าใช้จ่ายผี
```

## 7.3 โอนข้อมูลเก่าไป S3 (glacier pattern)

```
ข้อมูลที่ไม่ค่อยเข้าถึง:
  ✓ ย้ายไป S3 (ถูกกว่า DynamoDB มาก)
  ✓ เก็บ summary ใน DynamoDB

เทียบ: MySQL table partition + archive
```

## 7.4 TTL — ลบอัตโนมัติ (ฟรี)

```bash
# ตั้ง TTL attribute (epoch seconds)
update-time-to-live --time-to-live-specification "Enabled=true,AttributeName=expire_at"

★ ลบโดยไม่คิด WCU
★ เหมาะกับ: session, log, cache, temporary data
```

## 7.5 DAX (cache) — เมื่อ read-heavy

```
DAX = in-memory cache หน้า DynamoDB
  ✓ latency µs (จาก ms)
  ✓ ลด RCU
  ✗ เสียเงินเพิ่ม + cache invalidation

★ ใช้เมื่อ: อ่านซ้ำๆ เยอะ + ยอมรับ eventual consistency
```

## 7.6 ตั้ง CloudWatch Alarm

```
metrics ที่ควร monitor:
  ConsumedReadCapacityUnits
  ConsumedWriteCapacityUnits
  ReadThrottleEvents         ← ★ > 0 = โดน limit
  WriteThrottleEvents        ← ★
  SystemErrors
  UserErrors
  SuccessfulRequestLatency
```

---

# ส่วนที่ 8: Error Handling

## 8.1 Retry ด้วย Exponential Backoff

```
errors ที่ควร retry (transient):
  ProvisionedThroughputExceededException   ★
  ThrottlingException
  RequestTimeout
  InternalServerError
  ServiceUnavailable

errors ที่ไม่ควร retry:
  ValidationException
  ConditionalCheckFailedException
  ResourceNotFoundException
  ItemCollectionSizeLimitExceededException

★ AWS SDK ทำให้อัตโนมัติ (built-in retry)
   แต่ถ้าเขียนเอง → ใช้ exponential backoff + jitter
```

**เทียบ SQL:**
```sql
-- MySQL: deadlock → retry
-- DynamoDB: throttle → retry
```

## 8.2 ConditionalCheckFailedException

```
เมื่อ: ConditionExpression ไม่ผ่าน

★ ไม่ใช่ error ร้าย — เป็น "ผลลัพธ์ที่คาดได้"
   เช่น "สร้าง user ที่มีอยู่แล้ว" → condition ล้ม = ถูกต้องการนี้

ต้องแยก: ล้มเพราะ condition (ปกติ) vs ล้มเพราะ error (ต้องแก้)
```

## 8.3 UnprocessedItems ใน BatchWrite

```
BatchWrite อาจคืน UnprocessedItems (บางอันไม่สำเร็จ)

★ ต้อง retry UnprocessedItems (ด้วย backoff)
   ไม่งั้นข้อมูลหายเงียบๆ!
```

---

# ส่วนที่ 9: Security

## 9.1 IAM — least privilege

```json
{
  "Effect": "Allow",
  "Action": ["dynamodb:GetItem", "dynamodb:Query"],
  "Resource": [
    "arn:aws:dynamodb:REGION:ACCOUNT:table/app",
    "arn:aws:dynamodb:REGION:ACCOUNT:table/app/index/*"
  ]
}
```

```
★ อย่าใช้ dynamodb:* บน * (กว้างเกิน)
★ ระบุ table + index ที่ต้องการจริง
★ ⚠️ ต้องระบุ index/* ด้วย ไม่งั้น GSI query ไม่ได้
```

## 9.2 Encryption at Rest

```
✓ เปิดโดย default (AWS owned key)
✓ Optional: KMS customer-managed key (ควบคุมได้)

★ งานที่ต้อง compliance → ใช้ CMK
```

## 9.3 Fine-grained Access Control

```
ใช้ IAM condition บน leading key:
  "Condition": {
    "ForAllValues:StringEquals": {
      "dynamodb:LeadingKeys": ["${cognito-identity.amazonaws.com:sub}"]
    }
  }

→ user เห็นแค่ข้อมูลของตัวเอง (row-level security)
เทียบ SQL: RLS (row-level security) ของ PostgreSQL
```

---

# ส่วนที่ 10: Operations

## 10.1 Backup

```
✓ On-demand backup (manual, เก็บจนลบ)
✓ Point-in-time recovery (PITR, 35 วัน) ★ แนะนำเปิด
  → restore ไปวินาทีใดก็ได้ใน 35 วัน

★ PITR = ประกันภัย (เปิดไว้)
```

## 10.2 DynamoDB Streams

```
Stream = log การเปลี่ยนแปลง (INSERT/MODIFY/REMOVE)

ใช้กับ:
  ✓ trigger Lambda (เช่น sync ไป OpenSearch)
  ✓ audit log
  ✓ replicate ไป region อื่น
  ✓ ส่งเข้า Kinesis

เทียบ: MySQL binlog / CDC
```

## 10.3 Global Tables (multi-region)

```
Global Table = replicate table ข้าม region อัตโนมัติ

✓ active-active (write ได้ทุก region)
✓ latency ต่ำ (อ่าน local region)
✗ conflict resolution = last-writer-wins
✗ ต้องใช้ version attribute

★ ใช้เมื่อ: ผู้ใช้หลาย region + ต้องการ latency ต่ำ
```

## 10.4 NoSQL Workbench

```
เครื่องมือออกแบบของ AWS:
  ✓ visual data modeler
  ✓ query testing
  ✓ ดูว่า access pattern ใช้ key ถูกไหม

★ ใช้ตอนออกแบบ (ก่อนเขียนโค้ด)
```

---

# ส่วนที่ 11: สรุป Checklist

## 11.1 ตอนออกแบบ

```
[ ] เขียน access pattern ทั้งหมด ก่อนออกแบบ
[ ] PK กระจายดี? (ไม่ใช่ status/category/date)
[ ] ต้อง GSI กี่ตัว? (≤ 3)
[ ] มี LSI ที่ต้องใช้ไหม? (สร้างทีหลังไม่ได้!)
[ ] entity ควรอยู่ table เดียว (single-table) ไหม?
[ ] ทดสอบกับ NoSQL Workbench
```

## 11.2 ตอนเขียนโค้ด

```
[ ] ใช้ Query/GetItem ไม่ใช่ Scan
[ ] ใส่ Limit + pagination
[ ] ProjectionExpression เลือก field
[ ] UpdateItem แทน PutItem (เมื่อแก้บาง field)
[ ] ConditionExpression เมื่อสำคัญ
[ ] จัดการ UnprocessedItems (BatchWrite)
[ ] Retry ด้วย exponential backoff
[ ] Idempotency key สำหรับ operation ที่ retry ได้
[ ] ตรวจ --return-consumed-capacity ระหว่าง dev
```

## 11.3 ตอน production

```
[ ] เปิด PITR
[ ] ตั้ง CloudWatch Alarm (throttle, capacity)
[ ] IAM least privilege (ระบุ table + index)
[ ] ตัดสินใจ on-demand vs provisioned
[ ] ประเมินค่าใช้จ่ายล่วงหน้า (โดยเฉพาะ Scan!)
[ ] มี TTL สำหรับข้อมูลชั่วคราว
[ ] DAX ถ้า read-heavy
[ ] Global table ถ้าต้อง multi-region
```

## 11.4 ★ 10 กับดักที่พบบ่อย (สรุป)

```
① ออกแบบจาก entity แทน access pattern
② ใช้ status/category เป็น PK → hot partition
③ Scan เพราะ query ไม่ผ่าน key → แพง
④ คิดว่า Filter ลด RCU (ไม่ลด!)
⑤ ใช้ GSI เยอะเกิน → write แพง
⑥ ลืมว่า LSI สร้างทีหลังไม่ได้
⑦ PutItem แทน UpdateItem → ข้อมูลหาย
⑧ ไม่จัดการ UnprocessedItems → ข้อมูลหายเงียบๆ
⑨ ไม่มี idempotency key → retry แล้วซ้ำ
⑩ item ใกล้ 400 KB → error / กิน RCU มาก
```

---

# ส่วนที่ 12: เทียบ SQL Best Practices → DynamoDB

| SQL | DynamoDB |
|---|---|
| ออกแบบ schema จาก entity | ★ ออกแบบจาก access pattern |
| `CREATE INDEX` เมื่อ query ช้า | ★ ต้องวางแผน index ล่วงหน้า |
| `EXPLAIN` ดู query plan | `--return-consumed-capacity` |
| Partition table (ข้อมูลเยอะ) | Write sharding / TTL / S3 archive |
| `UNIQUE constraint` | ConditionExpression |
| `SELECT FOR UPDATE` | Optimistic lock (version) |
| Row-level security | Fine-grained IAM (LeadingKeys) |
| `binlog` / CDC | DynamoDB Streams |
| Replication | Global Tables |
| Connection pool | ⚠️ ไม่ต้อง (HTTP API) |
| `TRUNCATE` | ⚠️ ต้องลบทีละ item (หรือ recreate table) |

---

## ไฟล์ที่เกี่ยวข้อง

```
why-dynamodb.md               ← ทำไมต้องใช้
dynamodb-key-design.md        ← PK/SK/GSI/LSI
dynamodb-data-types.md        ← types ทั้งหมด
dynamodb-query-reference.md   ← API + prod safety
```
