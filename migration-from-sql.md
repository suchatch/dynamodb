# ย้ายจาก SQL/MongoDB มา DynamoDB — คู่มือ

> วิธีคิด + วิธีแปลง จากคนที่ถนัด SQL/MongoDB
> ตัวอย่าง generic (e-commerce) — ไม่มีข้อมูลองค์กร

---

# ส่วนที่ 1: ปรับวิธีคิดก่อน (สำคัญสุด)

## 1.1 ★ SQL Schema-driven → DynamoDB Query-driven

```
SQL / MongoDB:
  ① ออกแบบ schema/collection จาก entity
  ② normalize (แยกตาราง, ใช้ FK)
  ③ query อะไรก็ได้ (ด้วย JOIN / index)

DynamoDB:
  ① ★ เขียน access pattern ทั้งหมดก่อน
  ② denormalize (รวมข้อมูลให้ query ทีเดียวได้)
  ③ ออกแบบ key ให้ตอบ pattern
```

**ตัวอย่างจริง:**

```
โจทย์: ระบบขายของออนไลน์

วิธีคิดแบบ SQL (❌ ใช้กับ Dynamo ไม่ได้):
  users (user_id, name, email)
  orders (order_id, user_id, total, status, created_at)
  order_items (order_item_id, order_id, product_id, qty, price)
  products (product_id, name, price, stock)
  
  → query อะไรก็ได้ด้วย JOIN

วิธีคิดแบบ Dynamo (✅):
  ① access pattern:
     P1: ดู profile user        → user_id
     P2: ออเดอร์ของ user         → user_id + date
     P3: ออเดอร์ตาม status       → status + date
     P4: ดูออเดอร์ + รายการ       → order_id (มี items ซ้อน)
     P5: ดูสินค้า                 → product_id
     
  ② ออกแบบ:
     Table "app":
       PK=CUST#<id>,  SK=PROFILE                      → P1
       PK=CUST#<id>,  SK=ORDER#<date>#<order_id>      → P2 (มี items ใน M)
       PK=STATUS#<s>, SK=ORDER#<date>#<order_id>      → P3
       PK=ORDER#<id>, SK=DETAIL                        → P4
       PK=PROD#<id>,  SK=DETAIL                        → P5
```

## 1.2 ★ Normalize → Denormalize

```
SQL:      แยกตาราง → JOIN เอาคืน
DynamoDB: ★ เก็บซ้ำ → query ทีเดียว

ตัวอย่าง order + items:

❌ SQL norm:
  orders: { order_id, user_id, total }
  order_items: { order_item_id, order_id, product_id, qty }
  → ต้อง JOIN

✅ Dynamo denorm:
  {
    "PK": {"S": "CUST#u001"},
    "SK": {"S": "ORDER#2026-10-01#o123"},
    "order_id": {"S": "o123"},
    "total": {"N": "1500"},
    "items": {"L": [
      {"M": {"product_id": {"S":"p001"}, "qty": {"N":"2"}, "price": {"N":"500"}}},
      {"M": {"product_id": {"S":"p002"}, "qty": {"N":"1"}, "price": {"N":"500"}}}
    ]}
  }
  → 1 query ได้ทั้งออเดอร์ + รายการ
```

**เทียบ MongoDB:** คล้ายๆ embedded document (`$lookup` ก็มี แต่ช้า)

## 1.3 ★ ขนาดต่อ entity → เลือก index

```
SQL:      เพิ่ม index ทีหลังได้ (เมื่อเห็นว่า query ช้า)
DynamoDB: ★ ต้องวางแผน index ตั้งแต่ต้น
          LSI = สร้างทีหลังไม่ได้เลย!
```

---

# ส่วนที่ 2: แปลง Schema

## 2.1 Table → Table

```
SQL:
  CREATE TABLE users (
    user_id     VARCHAR(50) PRIMARY KEY,
    name        VARCHAR(100),
    email       VARCHAR(100),
    created_at  DATETIME
  );

DynamoDB:
  CreateTable:
    KeySchema:
      - AttributeName: user_id
        KeyType: HASH          ← Partition Key
    AttributeDefinitions:
      - AttributeName: user_id
        AttributeType: S
```

## 2.2 Composite PK

```
SQL:
  CREATE TABLE orders (
    user_id     VARCHAR(50),
    order_date  DATE,
    total       DECIMAL(10,2),
    PRIMARY KEY (user_id, order_date)
  );

DynamoDB:
  KeySchema:
    - {AttributeName: user_id,     KeyType: HASH}   ← PK
    - {AttributeName: order_date,  KeyType: RANGE}  ← SK
```

## 2.3 Foreign Key → ไม่มี (denormalize)

```
SQL:
  orders.user_id → users.user_id   (FOREIGN KEY)

DynamoDB:
  ★ ไม่มี FK — เก็บข้อมูลที่ต้องใช้ไว้ด้วยกัน
  หรือ เก็บ user_id ไว้ แล้ว query users แยก (2 round trips)
```

## 2.4 Index → GSI/LSI

```
SQL:
  CREATE INDEX idx_status ON orders (status);
  CREATE INDEX idx_email  ON users  (email);

DynamoDB:
  GlobalSecondaryIndexes:
    - IndexName: status-index
      KeySchema:
        - {AttributeName: status, KeyType: HASH}
        - {AttributeName: order_date, KeyType: RANGE}
      Projection: {ProjectionType: INCLUDE, NonKeyAttributes: [total]}

    - IndexName: email-index
      KeySchema:
        - {AttributeName: email, KeyType: HASH}
      Projection: {ProjectionType: KEYS_ONLY}
```

## 2.5 Data Types

```
SQL              →  DynamoDB
────────────────    ──────────────────
VARCHAR          →  S (String)
INT / BIGINT     →  N (Number, เก็บเป็น string)
DECIMAL(10,2)    →  N (หรือ integer × 100 สำหรับเงิน)
DATETIME         →  S (ISO 8601) หรือ N (epoch)
BOOLEAN          →  BOOL
TEXT             →  S
JSON             →  M (Map)
FOREIGN KEY      →  ❌ (denormalize)
```

---

# ส่วนที่ 3: แปลง Query

## 3.1 SELECT → GetItem / Query

```sql
-- SQL
SELECT * FROM users WHERE user_id = 'u001';
```
```
-- DynamoDB
GetItem:
  TableName: app
  Key: { "PK": {"S": "CUST#u001"}, "SK": {"S": "PROFILE"} }
```

```sql
-- SQL
SELECT * FROM orders
WHERE user_id = 'u001'
  AND order_date BETWEEN '2026-10-01' AND '2026-10-31'
ORDER BY order_date DESC
LIMIT 20;
```
```
-- DynamoDB
Query:
  KeyConditionExpression: "PK = :pk AND SK BETWEEN :d1 AND :d2"
  ExpressionAttributeValues: {
    ":pk": {"S": "CUST#u001"},
    ":d1": {"S": "ORDER#2026-10-01"},
    ":d2": {"S": "ORDER#2026-10-31"}
  }
  ScanIndexForward: false
  Limit: 20
```

## 3.2 ★ SELECT WHERE (ไม่ใช่ key) → GSI หรือ Scan

```sql
-- SQL (มี index บน status)
SELECT * FROM orders WHERE status = 'pending';
```
```
-- DynamoDB ที่มี GSI
Query:
  TableName: app
  IndexName: status-index
  KeyConditionExpression: "status = :s"
  ExpressionAttributeValues: { ":s": {"S": "pending"} }

-- DynamoDB ที่ "ไม่มี" GSI
Scan:  ← ❌ อ่านทั้ง table
  TableName: app
  FilterExpression: "status = :s"
```

## 3.3 ★ JOIN → ไม่มี (แยก query หรือ denormalize)

```sql
-- SQL
SELECT o.order_id, o.total, u.name
FROM orders o
JOIN users u ON o.user_id = u.user_id
WHERE o.user_id = 'u001';
```
```
-- DynamoDB ทางเลือก 1: denormalize (เก็บ name ไว้ใน order)
Query: PK="CUST#u001" → ได้ order ที่มี name อยู่แล้ว ✓

-- DynamoDB ทางเลือก 2: 2 queries (ถ้าไม่ denorm)
1. Query orders ของ u001
2. GetItem user profile
→ รวมในโค้ดแอป
```

## 3.4 ★ GROUP BY / COUNT → ไม่มี

```sql
-- SQL
SELECT status, COUNT(*) FROM orders GROUP BY status;
```
```
-- DynamoDB: หลายทางเลือก

① Denormalize + atomic counter (เก็บ count ไว้ใน item)
   UpdateExpression: "ADD pending_count :one"
   GetItem → อ่าน count ทันที ✓

② Streams + Lambda (นับแบบ async)
   Stream → Lambda → update counter item

③ Scan (❌ ช้า/แพง — เฉพาะข้อมูลน้อย)

★ ไม่มี GROUP BY ที่ดีใน DynamoDB → pre-aggregate
```

## 3.5 ★ SUM / AVG → pre-aggregate

```sql
-- SQL
SELECT user_id, SUM(total) FROM orders GROUP BY user_id;
```
```
-- DynamoDB: เก็บ running total ใน item (maintain ตอน write)

Item "CUST#u001" / "STATS":
  { "total_spent": {"N": "12500"}, "order_count": {"N": "8"} }

UpdateExpression: "ADD total_spent :amt, order_count :one"
→ อ่านค่าสรุปได้ทันที (ไม่ต้อง aggregate)
```

## 3.6 UPDATE → UpdateItem

```sql
-- SQL
UPDATE users SET name = 'Somchai', updated_at = NOW()
WHERE user_id = 'u001';
```
```
-- DynamoDB
UpdateItem:
  Key: { "PK": {"S": "CUST#u001"}, "SK": {"S": "PROFILE"} }
  UpdateExpression: "SET #n = :name, updated_at = :ts"
  ExpressionAttributeNames: { "#n": "name" }
  ExpressionAttributeValues: {
    ":name": {"S": "Somchai"},
    ":ts": {"S": "2026-10-13T10:00:00Z"}
  }
```

## 3.7 ★ Transaction → TransactWriteItems (จำกัด)

```sql
-- SQL
BEGIN;
  UPDATE accounts SET balance = balance - 1000 WHERE id='a1';
  UPDATE accounts SET balance = balance + 1000 WHERE id='a2';
COMMIT;
```
```
-- DynamoDB
TransactWriteItems:
  TransactItems: [
    { Update: { Key: {a1}, UpdateExpression: "SET balance = balance - :amt",
                ConditionExpression: "balance >= :amt" } },
    { Update: { Key: {a2}, UpdateExpression: "SET balance = balance + :amt" } }
  ]
★ ≤ 100 operations ต่อ transaction
```

## 3.8 ตารางเทียบคำสั่งครบ

| SQL | DynamoDB |
|---|---|
| `SELECT WHERE pk=x LIMIT 1` | GetItem |
| `SELECT WHERE pk=x` | Query |
| `SELECT WHERE pk=x AND sk>y` | Query + KeyCondition |
| `SELECT WHERE other=z` | ★ GSI (หรือ Scan) |
| `SELECT *` | Scan ❌ |
| `SELECT col1, col2` | ProjectionExpression |
| `WHERE col > x` (ไม่ใช่ key) | FilterExpression (⚠️ ไม่ลด RCU) |
| `ORDER BY` | Sort Key (`ScanIndexForward`) |
| `LIMIT` | `Limit` |
| `OFFSET` | `ExclusiveStartKey` |
| `INSERT` | PutItem |
| `UPDATE SET` | UpdateItem |
| `REPLACE` | PutItem |
| `DELETE` | DeleteItem |
| `BEGIN...COMMIT` | TransactWriteItems |
| `JOIN` | ❌ denormalize |
| `GROUP BY` | ❌ pre-aggregate |
| `COUNT(*)` | ⚠️ Scan / counter item |
| `SUM/AVG` | pre-aggregate / Streams |
| `TRUNCATE` | ⚠️ ลบทีละ item |

---

# ส่วนที่ 4: ตัวอย่างครบชุด — Blog

## 4.1 SQL Schema

```sql
CREATE TABLE users (
  user_id    VARCHAR(50) PRIMARY KEY,
  name       VARCHAR(100),
  email      VARCHAR(100) UNIQUE,
  created_at DATETIME
);

CREATE TABLE posts (
  post_id    VARCHAR(50) PRIMARY KEY,
  user_id    VARCHAR(50),
  title      VARCHAR(200),
  body       TEXT,
  status     VARCHAR(20),
  created_at DATETIME,
  FOREIGN KEY (user_id) REFERENCES users(user_id)
);

CREATE INDEX idx_posts_user   ON posts(user_id);
CREATE INDEX idx_posts_status ON posts(status);
```

## 4.2 Access Patterns

```
① ดู profile user                     
② โพสต์ทั้งหมดของ user
③ ดูโพสต์เดี่ยว
④ โพสต์ตาม status (published/draft)
⑤ ดูโพสต์ + comment ทั้งหมด
⑥ นับโพสต์ของ user
```

## 4.3 DynamoDB Design

```
Table "blog":
  PK = "USER#<user_id>"    SK = "PROFILE"
  PK = "USER#<user_id>"    SK = "POST#<post_id>"
  PK = "POST#<post_id>"    SK = "DETAIL"
  PK = "POST#<post_id>"    SK = "COMMENT#<ts>"
  PK = "STATUS#<status>"   SK = "POST#<ts>#<post_id>"

GSI:
  "gsi-status"  PK = "STATUS#<status>"  SK = "POST#<ts>#<post_id>"

Mapping:
  ① GetItem  PK=USER#u001, SK=PROFILE
  ② Query    PK=USER#u001, SK begins_with "POST#"
  ③ GetItem  PK=POST#p001, SK=DETAIL
  ④ Query    GSI gsi-status, PK=STATUS#published
  ⑤ Query    PK=POST#p001, SK begins_with "COMMENT#"
  ⑥ เก็บ counter ใน PROFILE item (ADD ตอน create post)
```

## 4.4 ตัวอย่าง Item

```json
// ① user profile
{
  "PK": {"S": "USER#u001"},
  "SK": {"S": "PROFILE"},
  "user_id": {"S": "u001"},
  "name": {"S": "Somchai"},
  "email": {"S": "user@example.com"},
  "post_count": {"N": "12"},
  "created_at": {"S": "2026-01-15T08:00:00Z"}
}

// ② post (อยู่ใน partition ของ user)
{
  "PK": {"S": "USER#u001"},
  "SK": {"S": "POST#p001"},
  "post_id": {"S": "p001"},
  "title": {"S": "DynamoDB for SQL devs"},
  "status": {"S": "published"},
  "created_at": {"S": "2026-10-13T10:00:00Z"},
  "GSI1PK": {"S": "STATUS#published"},
  "GSI1SK": {"S": "POST#2026-10-13T10:00:00Z#p001"}
}

// ⑤ comment
{
  "PK": {"S": "POST#p001"},
  "SK": {"S": "COMMENT#2026-10-13T11:00:00Z"},
  "user_id": {"S": "u002"},
  "body": {"S": "Great post!"},
  "created_at": {"S": "2026-10-13T11:00:00Z"}
}
```

---

# ส่วนที่ 5: Migration จริง (มีข้อมูลอยู่แล้ว)

## 5.1 ★ ถ้ามีข้อมูลใน SQL แล้ว ต้องย้าย

```
ขั้นตอน:
① ออกแบบ DynamoDB schema + access pattern
② ทดสอบ schema (NoSQL Workbench) — ก่อนย้ายจริง!
③ Export ข้อมูลจาก SQL (ตาราง → CSV/JSON)
④ Transform (denormalize, แปลง type, สร้าง key)
⑤ Import เข้า DynamoDB (batch write)
⑥ ★ Sync ข้อมูลใหม่ระหว่าง migrate (dual-write / CDC)
⑦ สลับ app มาใช้ DynamoDB
⑧ Observe → ปิด SQL เดิม (ถ้าไม่ต้อง dual)
```

## 5.2 Dual-write ในช่วง migrate

```
ช่วง migrate:
  app เขียนทั้ง SQL และ DynamoDB
  → อ่านจาก SQL (ยังไม่สลับ)
  → เทียบข้อมูล (verify)
  → เมื่อมั่นใจ → อ่านจาก DynamoDB
  → หยุดเขียน SQL
```

**เทียบ:**
```
เหมือน migrate database ทั่วไป:
  dual-write → verify → switch read → stop old write
```

## 5.3 Import ข้อมูลเยอะ

```
✓ BatchWriteItem (25 items ต่อครั้ง) — สำหรับข้อมูลเล็ก
✓ AWS Data Pipeline / Glue — สำหรับข้อมูลเยอะ
✓ S3 → DynamoDB import (native, เร็วสุด)
   (ต้อง format DynamoDB JSON)

★ ระวัง: อย่าใช้ PutItem ทีละตัว (ช้ามาก)
★ ระวัง: import เข้า table ที่มี traffic → กระทบ throughput
   → ทำนอก peak hour / ใช้ on-demand
```

---

# ส่วนที่ 6: ★ กับดักตอน migrate

```
① พยายามรักษา schema เดิม → ไม่ได้
   ✅ ออกแบบใหม่แบบ query-driven

② ใช้ Scan เพราะ "ยังไม่ได้ทำ GSI"
   ✅ ออกแบบ GSI ตั้งแต่แรก (อย่าเลื่อน)

③ คิดว่าจะเพิ่ม index ทีหลังได้เสมอ
   ❌ LSI สร้างทีหลังไม่ได้!
   ✅ วางแผนครบก่อน

④ JOIN ใน app (N+1 query)
   ❌ query 100 ครั้ง (ช้า)
   ✅ denormalize หรือใช้ GSI

⑤ migrate แล้ว data ไม่ตรง
   ✅ dual-write + verify ก่อนสลับ

⑥ ใช้ PutItem import ทีละตัว → ช้า
   ✅ BatchWrite / S3 import

⑦ ลืมจัดการ delta (ข้อมูลใหม่ระหว่าง migrate)
   ✅ dual-write / CDC / replay

⑧ ลืม TTL → data สะสม
   ✅ ตั้ง TTL สำหรับข้อมูลชั่วคราว
```

---

# ส่วนที่ 7: เปรียบเทียบ mental model

```
หัวข้อ              SQL/MongoDB              DynamoDB
──────────────────  ───────────────────────  ─────────────────────────
จุดเริ่ม            entity / schema          ★ access pattern
Design              normalize                ★ denormalize
PK                  เลือกได้อิสระ              ★ คุม shard (ต้องกระจาย)
Index               เพิ่มทีหลังได้             ★ วางแผนล่วงหน้า (LSI ไม่ได้)
JOIN                ✅                        ❌
GROUP BY            ✅                        ❌ (pre-aggregate)
Aggregate           query-time                ★ write-time (pre-aggregate)
Transaction         ✅ เต็ม                    ~ ≤ 100 ops
Query flexibility   ✅ สูง                     ★ จำกัด (ตาม key)
Scan cost           ~ (full table scan)        ★★ แพงมาก
ขีดจำกัด item        row ~ ยืดหยุ่น            400 KB (แข็ง)
Cost model          เครื่อง/เดือน              ★ ตาม usage
Scale               vertical/sharding เอง      ★ auto
```

---

# ส่วนที่ 8: Checklist ก่อนเริ่ม migrate

```
ออกแบบ (ก่อนแตะข้อมูล)
[ ] เขียน access pattern ทั้งหมด
[ ] ออกแบบ key (PK กระจาย, SK มีความหมาย)
[ ] ออกแบบ GSI (≤3) / LSI (ถ้าจำเป็น — สร้างทีหลังไม่ได้!)
[ ] ทดสอบ schema (NoSQL Workbench)
[ ] ตัดสินใจ single-table vs multi-table

Migrate
[ ] Export จาก SQL
[ ] Transform (denormalize, แปลง type)
[ ] Import (batch / S3)
[ ] dual-write สำหรับข้อมูลใหม่
[ ] verify ข้อมูลตรงกัน

App
[ ] เปลี่ยน query เป็น GetItem/Query (ไม่ Scan)
[ ] ลบ JOIN ในโค้ด → denormalize
[ ] ลบ GROUP BY ในโค้ด → pre-aggregate
[ ] retry + idempotency
[ ] ตรวจ --return-consumed-capacity

Production
[ ] เปิด PITR
[ ] CloudWatch alarm
[ ] IAM least privilege
[ ] ประเมินค่าใช้จ่าย
```

---

# ส่วนที่ 9: ถ้าอยากรู้ว่าควร migrate ไหม

```
★ ควร migrate เมื่อ:
  ✓ ต้องการ scale อัตโนมัติ (ไม่ต้อง manage)
  ✓ traffic ขึ้นๆ ลงๆ (จ่ายตามใช้)
  ✓ access pattern ชัดเจน (รู้ query ล่วงหน้า)
  ✓ key-value / document ไม่ต้องการ JOIN
  ✓ ใช้ serverless (Lambda) เป็นหลัก

★ ไม่ควร migrate เมื่อ:
  ✗ ต้อง JOIN / relation ซับซ้อน
  ✗ ต้อง ad-hoc query (analyst query)
  ✗ งานรายงานที่ aggregate ซับซ้อน
  ✗ ข้อมูลน้อย (< 1000 rows) — ไม่คุ้ม
  ✗ ทีมยังไม่พร้อม (โค้งเรียนสูง)
  ✗ ต้องการ SQL เต็มรูปแบบ → ใช้ Aurora/RDS

★ ทางเลือกกลาง:
  ✓ ใช้ทั้ง 2: SQL (transaction) + DynamoDB (scale/hot path)
  ✓ หรือ: SQL → เริ่ม, DynamoDB → เมื่อเจอข้อจำกัด
```

---

## ไฟล์ที่เกี่ยวข้อง

```
why-dynamodb.md               ← ทำไมต้องใช้ (decision matrix)
dynamodb-key-design.md        ← PK/SK/GSI/LSI
dynamodb-data-types.md        ← types
dynamodb-query-reference.md   ← API + prod safety
dynamodb-best-practices.md    ← แนวปฏิบัติที่ดี
```
