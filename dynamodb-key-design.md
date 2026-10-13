# DynamoDB Key Design — Reference

> Primary Key, Sort Key, GSI, LSI — หัวใจของ DynamoDB
> เทียบกับ MySQL / MongoDB ทุกหัวข้อ
> ตัวอย่างใช้ e-commerce ทั่วไป (generic)

---

# ส่วนที่ 1: Primary Key

## 1.1 ทำไม key สำคัญที่สุด

```
ใน MySQL:  เลือก PK ผิด → แต่ยัง query อะไรก็ได้ (index ช่วย)
ใน MongoDB: เลือก shard key ผิด → re-shard เจ็บ แต่ query ยังยืดหยุ่น
ใน DynamoDB: ★ เลือก key ผิด → query ที่ต้องการทำไม่ได้เลย
                                 (ต้องสร้าง index ใหม่ / migrate)
```

**เทียบให้เห็นภาพ:**
```
MySQL = บ้านที่มีประตูทุกด้าน (เข้าได้ทุกทาง)
DynamoDB = บ้านที่มีประตูเดียว (เข้าได้ทางเดียว — ต้องเลือกให้ถูก)
```

## 1.2 Simple Primary Key (Partition Key เดียว)

```
Table: users

┌────────────────────┬─────────────────────────┐
│ Partition Key      │ Attributes              │
│ (user_id)          │                         │
├────────────────────┼─────────────────────────┤
│ "u001"             │ {name, email, ...}      │
│ "u002"             │ {name, email, ...}      │
│ "u003"             │ {name, email, ...}      │
└────────────────────┴─────────────────────────┘

★ PK ต้องไม่ซ้ำ (unique)
เทียบ MySQL: PRIMARY KEY (user_id)
```

**Query ที่ทำได้:**
```
✓ GET user ที่ user_id = "u001"          (ตรงไปที่ item)
✗ GET user ที่ email = "..."             (ไม่ได้! ต้องมี GSI)
✗ GET user ที่ name ขึ้นต้นด้วย "S"       (ไม่ได้!)
```

## 1.3 Composite Primary Key (Partition Key + Sort Key) ★

```
Table: orders

┌──────────────┬──────────────────┬────────────────────────┐
│ Partition Key│ Sort Key         │ Attributes             │
│ (user_id)    │ (order_date)     │                        │
├──────────────┼──────────────────┼────────────────────────┤
│ "u001"       │ "2026-10-01"     │ {total: 450, ...}      │
│ "u001"       │ "2026-10-05"     │ {total: 1200, ...}     │
│ "u001"       │ "2026-10-12"     │ {total: 300, ...}      │
│ "u002"       │ "2026-10-03"     │ {total: 890, ...}      │
└──────────────┴──────────────────┴────────────────────────┘

★ PK ซ้ำได้ แต่ PK + SK ต้องไม่ซ้ำ
เทียบ MySQL: PRIMARY KEY (user_id, order_date)
เทียบ MongoDB: compound index { user_id: 1, order_date: 1 }
```

**Query ที่ทำได้ (ดูว่าเพิ่มขึ้นเยอะ!):**
```
✓ ออเดอร์ทั้งหมดของ u001
  → Query: PK = "u001"

✓ ออเดอร์ของ u001 ในเดือน ต.ค.
  → Query: PK = "u001" AND SK BETWEEN "2026-10-01" AND "2026-10-31"

✓ ออเดอร์ของ u001 เรียงตามวันที่ (ใหม่→เก่า)
  → Query: PK = "u001", ScanIndexForward = false

✓ ออเดอร์ของ u001 หลัง 5 ต.ค.
  → Query: PK = "u001" AND SK > "2026-10-05"

✗ ออเดอร์ทั้งหมดของ "วันนี้" (ข้ามทุก user)
  → ไม่ได้! (ต้องมี GSI)

✗ ออเดอร์ที่ยอด > 1000 (ข้ามทุก user)
  → ไม่ได้! (ต้องมี GSI)
```

**★ บทเรียน:** Sort Key ทำให้ query ในกลุ่ม PK เดียวกันยืดหยุ่นขึ้นมาก

---

# ส่วนที่ 2: Partition Key — เลือกยังไง (สำคัญสุด)

## 2.1 Partition Key = ตัวตัดสินว่าไป shard ไหน

```
DynamoDB แบ่งข้อมูลเป็น partition (ตาม hash ของ PK)

PK = "u001"  → hash → partition A
PK = "u002"  → hash → partition B
PK = "u003"  → hash → partition A
PK = "u004"  → hash → partition C

★ AWS กระจายให้อัตโนมัติ — แต่ถ้า PK เลือกผิด → กระจายไม่ได้
```

## 2.2 ★ Hot Partition — ปัญหาที่พบบ่อยสุด

```
❌ ตัวอย่างที่ผิด: ใช้ status เป็น PK

┌──────────────────┬────────────────────────┐
│ PK = status      │                        │
├──────────────────┼────────────────────────┤
│ "active"         │ 900,000 items  ★★★    │  ← ทุกอย่างกองที่นี่
│ "inactive"       │  90,000 items          │
│ "deleted"        │  10,000 items          │
└──────────────────┴────────────────────────┘

ปัญหา:
  - "active" มี 900k items → ไป partition เดียว (หรือไม่กี่ตัว)
  - partition มีขีดจำกัด: 3,000 RCU / 1,000 WCU ต่อ partition
  - → query ช้า, write ถูก throttle (ProvisionedThroughputExceeded)

เทียบ MySQL: เหมือน index ที่ทุก row มีค่าเดียวกัน → ไร้ประโยชน์
```

## 2.3 PK ที่ดี vs ไม่ดี

| PK | ดีไหม | เหตุผล |
|---|---|---|
| `user_id` | ✅ ดี | ค่าเยอะ กระจายทั่ว |
| `order_id` (uuid) | ✅ ดี | กระจายสม่ำเสมอ |
| `status` | ❌ แย่ | ค่าไม่กี่แบบ → hot |
| `category` | ❌ แย่ | ค่าไม่กี่แบบ |
| `country` | ⚠️ พอได้ | ถ้ามีหลายประเทศ + traffic กระจาย |
| `date` (YYYY-MM-DD) | ❌ แย่ | วันนี้ทุก write ไปวันที่เดียว ★ |
| `created_at` (timestamp) | ❌ แย่ | เหมือน date |
| `date#uuid` | ✅ ดี | ★ ผสมเพื่อกระจาย |

## 2.4 ★ เทคนิคแก้: Write Sharding (เติม suffix)

```
ปัญหา: PK = date (ทุก write วันนี้ไป partition เดียว)

แก้: PK = date#random_suffix
  "2026-10-13#1"
  "2026-10-13#2"      ← กระจาย 10 partition
  "2026-10-13#3"
  ...
  "2026-10-13#10"

Query: ต้อง query ทั้ง 10 partition แล้วรวมผล (หรือเก็บ meta ว่าใช้ suffix อะไร)
```

**เทียบ MongoDB:** `hashed shard key` (กระจายคล้ายกัน)

## 2.5 PK แบบ Composite (สร้างจากหลายค่า)

```
ต้องการ: PK ที่กระจาย + มีความหมาย

ตัวอย่าง:
  PK = "CUST#u001"        (prefix บอก entity type)
  PK = "CUST#u002"
  PK = "PROD#p123"
  → กระจายดี (prefix ต่างกัน)

หรือ hierarchy:
  PK = "u001#product"
  PK = "u001#order"
  SK = "product#123" / "order#2026-10-01"
  → เก็บหลาย entity ใน partition เดียว (single-table design)
```

---

# ส่วนที่ 3: Sort Key — เลือกยังไง

## 3.1 Sort Key ให้อะไร

```
ภายใน Partition Key เดียวกัน Sort Key ช่วยให้:
  ① เรียงลำดับ (ORDER BY)
  ② ช่วง (BETWEEN, >, <)
  ③ ขึ้นต้นด้วย (begins_with)
  ④ ดึงหลาย item พร้อมกัน (batch)
```

## 3.2 ตัวอย่าง Sort Key ที่ดี

```
Table: orders (PK = user_id, SK = order_date)

SK = "2026-10-01"     ← เรียงตามวันที่, query ช่วงได้
SK = "2026-10-05"
SK = "2026-10-12"

Query:
  PK = "u001"                              → ทั้งหมด
  PK = "u001" AND SK > "2026-10-05"        → หลังวันที่นั้น
  PK = "u001" AND begins_with(SK, "2026-10") → เดือน ต.ค.
```

## 3.3 Sort Key แบบ Composite (รวมหลายค่า)

```
สมมติต้อง query:
  ① ออเดอร์ของ user ทั้งหมด
  ② ออเดอร์ของ user ตามสถานะ
  ③ ออเดอร์ของ user ตามวันที่

ใช้ SK = "status#date":
  "pending#2026-10-01"
  "pending#2026-10-05"
  "shipped#2026-10-02"
  "completed#2026-10-03"

Query:
  PK="u001"                          → ทั้งหมด
  PK="u001" AND begins_with(SK,"pending#")  → pending ทั้งหมด ★
  PK="u001" AND SK BETWEEN "pending#2026-10-01" AND "pending#2026-10-31"
                                     → pending เดือน ต.ค.

⚠️ เรียงตาม status ก่อน แล้วค่อย date
   (ลำดับใน composite key สำคัญ!)
```

**★ เลือกลำดับให้ตรงกับ query ที่ใช้บ่อยสุด**

| ต้องการ | SK format |
|---|---|
| เรียงตามวันที่ | `date` |
| กรอง status แล้วเรียงวันที่ | `status#date` |
| กรอง category + เรียงราคา | `category#price` |

---

# ส่วนที่ 4: Secondary Index — GSI vs LSI

## 4.1 ปัญหาที่ index แก้

```
Table: orders (PK = user_id, SK = order_date)

Query ที่ทำได้:
  ✓ ออเดอร์ของ user
  ✓ ออเดอร์ของ user ในช่วงวันที่

Query ที่ทำไม่ได้:
  ✗ ออเดอร์ทุกอันที่ status = "pending"
  ✗ ออเดอร์ทุกอันในเดือน ต.ค. (ข้าม user)
  ✗ ออเดอร์ที่ยอด > 1000

→ ★ ต้องมี Secondary Index
```

## 4.2 GSI (Global Secondary Index)

```
GSI = "table เสมือน" ที่มี key คนละชุด

Table หลัก:  PK = user_id      SK = order_date
GSI 1:       PK = status       SK = order_date
GSI 2:       PK = order_id     (ไม่มี SK)

ข้อดี:
  ✓ PK ต่างจาก table ได้
  ✓ สร้างตอนสร้าง table หรือ ★ เพิ่มทีหลังได้
  ✓ 20 ตัวต่อ table

ข้อเสีย:
  ✗ eventual consistency เท่านั้น (อ่านอาจไม่ทันสมัย)
  ✗ คิดค่า RCU/WCU แยก (จ่ายเพิ่ม)
  ✗ เพิ่มทีหลัง → backfill ช้า (ถ้าข้อมูลเยอะ)
```

**ตัวอย่าง:**
```
Table: orders
  PK = user_id, SK = order_date

GSI "status-index":
  PK = status, SK = order_date
  → query: status = "pending"

GSI "order-lookup":
  PK = order_id
  → GET order ด้วย order_id (แบบเร็ว)
```

## 4.3 LSI (Local Secondary Index)

```
LSI = index ที่มี PK เดียวกัน แต่ SK ต่าง

Table หลัก:  PK = user_id  SK = order_date
LSI 1:       PK = user_id  SK = total_amount     ★ PK ต้องเหมือน

ข้อดี:
  ✓ strong consistency ได้
  ✓ ไม่คิด RCU/WCU แยก (ใช้ของ table)

ข้อเสีย:
  ✗ ★ ต้องสร้างตอนสร้าง table เท่านั้น (เพิ่มทีหลังไม่ได้!)
  ✗ 5 ตัวต่อ table
  ✗ ≤ 10 GB ต่อ partition
```

## 4.4 ★ ตารางเทียบ GSI vs LSI

| | GSI | LSI |
|---|---|---|
| Partition Key | **ต่างจาก table ได้** | ต้องเหมือน table |
| Sort Key | ต่างได้ | ต่างได้ |
| สร้างเมื่อไหร่ | ตอนสร้าง **หรือเพิ่มทีหลังได้** | ★ **ตอนสร้างเท่านั้น** |
| จำนวนสูงสุด | 20 | 5 |
| Consistency | eventual เท่านั้น | eventual / strong |
| Capacity | คิด RCU/WCU แยก | ใช้ของ table |
| ขนาด | ไม่จำกัด | ≤ 10 GB/partition |
| ลบได้ | ✅ | ✅ (แต่สร้างใหม่ไม่ได้) |

**เทียบ:**
```
MySQL:     CREATE INDEX หลังสร้าง table ได้ (เหมือน GSI)
           ★ ไม่มีอะไรเหมือน LSI (ข้อจำกัดเพิ่มทีหลัง)
MongoDB:   createIndex ทีหลังได้ (เหมือน GSI)
```

## 4.5 ★ เมื่อไหร่ใช้ GSI vs LSI

```
ใช้ GSI เมื่อ:
  ✓ ต้องการ PK ที่ต่างจาก table (กรณีส่วนใหญ่)
  ✓ ยังไม่รู้ index ที่ต้องการล่วงหน้า (เพิ่มทีหลังได้)
  ✓ ข้อมูลเยอะ (> 10 GB ต่อ partition)

ใช้ LSI เมื่อ:
  ✓ ต้องการ strong consistency บน index
  ✓ PK เดียวกัน + ต่างแค่ sort
  ✓ รู้ตั้งแต่แรก ว่าต้องการ (สร้างทีหลังไม่ได้!)
  ✓ ข้อมูลไม่เยอะ (< 10 GB ต่อ partition)
```

## 4.6 ★★ กับดักเรื่อง LSI

```
★ LSI สร้างทีหลังไม่ได้ — เพิ่มได้เฉพาะตอน CreateTable

ถ้าลืม:
  → ต้อง migrate: สร้าง table ใหม่ + copy data + สลับ (zero-downtime)
  → เจ็บมาก

ดังนั้น: วางแผน index ครบ ตั้งแต่ตอนออกแบบ
```

---

# ส่วนที่ 5: Query API — ใช้ key ยังไง

## 5.1 GetItem (ดึง item เดียว — เร็วสุด)

```
GetItem:
  TableName: users
  Key: { user_id: {S: "u001"} }

→ คืน 1 item (หรือ "not found")
→ เทียบ MySQL: SELECT * FROM users WHERE user_id='u001' LIMIT 1
```

## 5.2 Query (ใช้ key — แนะนำ)

```
Query:
  TableName: orders
  KeyConditionExpression: "user_id = :uid AND order_date BETWEEN :d1 AND :d2"
  ExpressionAttributeValues: {
    ":uid": {S: "u001"},
    ":d1":  {S: "2026-10-01"},
    ":d2":  {S: "2026-10-31"}
  }
  ScanIndexForward: false      // เรียงใหม่→เก่า

→ เทียบ MySQL: WHERE user_id='u001' AND order_date BETWEEN ... 
```

**★ Query ต้องมี KeyConditionExpression ที่ใช้ PK (และ SK ได้)**

**เพิ่ม FilterExpression (กรองหลังดึง):**
```
Query:
  KeyConditionExpression: "user_id = :uid"           ← ใช้ key (ฟรี)
  FilterExpression: "total_amount > :amt"            ← ★ กรองหลังดึง
  ExpressionAttributeValues: {":uid": {S:"u001"}, ":amt": {N:"1000"}}
```

**⚠️ FilterExpression กรอง "หลัง" อ่าน:**
```
Query ดึง 100 items → filter เหลือ 10
จ่าย RCU ตาม 100 items (ไม่ใช่ 10)

เทียบ: MySQL WHERE ที่ไม่ใช้ index → scan แล้วกรอง
→ ถ้ากรองเยอะๆ บ่อย → ควรสร้าง GSI
```

## 5.3 Scan (อ่านทั้ง table — ❌ เลี่ยง)

```
Scan:
  TableName: orders
  FilterExpression: "status = :s"
  ExpressionAttributeValues: {":s": {S:"pending"}}

→ อ่านทุก item แล้วกรอง
→ ★ ช้า + แพง (จ่ายตามข้อมูลที่อ่านทั้งหมด)

เทียบ MySQL: SELECT * FROM orders WHERE status='pending' (โดยไม่มี index)
→ full table scan
```

## 5.4 ตารางเทียบ

| DynamoDB | MySQL | ราคา/ความเร็ว |
|---|---|---|
| GetItem | `WHERE pk = x` (PK lookup) | 🟢 เร็วสุด |
| Query | `WHERE pk = x AND sk ...` | 🟢 เร็ว (ตาม key) |
| Query + Filter | `WHERE pk = x AND other` | 🟡 อ่านเยอะกว่าที่ได้ |
| Scan | full table scan | 🔴 ช้า + แพง |
| Scan + Filter | full scan + where | 🔴🔴 แพงสุด |

---

# ส่วนที่ 6: การออกแบบ — ขั้นตอน

## 6.1 ★ Query-first design (5 ขั้น)

```
① เขียน query ที่ระบบต้องทำ ทั้งหมด (ทุกหน้าจอ/ฟีเจอร์)
   "หน้าออเดอร์: แสดงออเดอร์ของ user เรียงใหม่→เก่า"
   "หน้าจัดการ: แสดงออเดอร์ status=pending ทั้งหมด"

② ระบุ "access pattern" ของแต่ละ query
   (ใช้ key อะไร, กรองอะไร, เรียงยังไง)

③ ออกแบบ table key ให้ตอบ pattern ที่พบบ่อยสุด

④ ออกแบบ GSI สำหรับ pattern ที่เหลือ

⑤ ตรวจว่า pattern ที่หลงเหลือไม่ต้อง Scan
```

## 6.2 ตัวอย่างจริง (e-commerce)

**Access patterns:**
```
① ดูโปรไฟล์ user         → GetItem (PK: user_id)
② ออเดอร์ของ user        → Query (PK: user_id)
③ ออเดอร์ของ user เดือนนี้ → Query (PK + SK between)
④ ดูออเดอร์เดี่ยว         → GSI (PK: order_id)
⑤ ออเดอร์ status pending  → GSI (PK: status)
⑥ สินค้าตามหมวด           → Query (PK: category) หรือ GSI
```

**ออกแบบ:**
```
Table "shop":
  PK = "USER#u001"   SK = "PROFILE"          → ①
  PK = "USER#u001"   SK = "ORDER#2026-10-01" → ②③
  PK = "ORDER#o123"  SK = "DETAIL"           → GSI ใช้ query ④
  PK = "STATUS#pending" SK = "ORDER#o123"    → ⑤ (หรือ GSI)

GSI "gsi-order-id":
  PK = "ORDER#o123"
  → query ④

GSI "gsi-status":
  PK = "STATUS#pending", SK = "date"
  → query ⑤
```

**★ นี่คือ single-table design** — entity หลายชนิดใน table เดียว (pattern ที่ DynamoDB แนะนำ)

## 6.3 Single-table vs Multi-table

| | Multi-table (แบบ SQL) | Single-table |
|---|---|---|
| Table | 1 entity = 1 table | หลาย entity ใน 1 table |
| JOIN | ต้อง denormalize | ★ อยู่ใน partition เดียว → query ทีเดียว |
| เรียนรู้ | ง่าย (คุ้นจาก SQL) | ยาก (ต้องคิดแบบ DynamoDB) |
| เหมาะกับ | ทีมใหม่ / งานเล็ก | งานจริงจัง / performance สูง |

**เทียบ MySQL:**
```sql
-- Multi-table (SQL ปกติ)
SELECT u.name, o.total FROM users u JOIN orders o ON u.id = o.user_id;

-- Single-table (DynamoDB)
-- Query PK="USER#u001" → ได้ทั้ง profile และ orders ในคำสั่งเดียว!
```

---

# ส่วนที่ 7: กับดัก key design

```
① ใช้ status/category/type เป็น PK → hot partition
   ✅ ใช้ค่าที่กระจายเยอะ (user_id, uuid) หรือเติม suffix

② ลืม index ที่ต้องใช้ → เพิ่มทีหลัง
   ✅ วางแผน access pattern ครบก่อนออกแบบ
   ★ LSI เพิ่มทีหลังไม่ได้เลย!

③ ใช้ date เป็น PK → วันนี้ทุก write ไป partition เดียว
   ✅ date#suffix (write sharding) หรือใช้ date เป็น SK

④ คิดว่า 1 table = 1 entity → ต้อง JOIN
   ✅ single-table design (หลาย entity 1 table)

⑤ FilterExpression ถูกกว่า Query
   ❌ ผิด! Filter กรองหลังอ่าน → จ่ายเท่าเดิม
   ✅ ถ้ากรองบ่อย → สร้าง GSI

⑥ Scan ข้อมูลน้อยๆ ก็ ok
   ❌ Scan คิด RCU ตามข้อมูลที่อ่านทั้งหมด
   ✅ ใช้ Query + GSI แทน

⑦ Sort Key ไม่สำคัญ
   ❌ SK ตัดสิน query ที่ทำได้ในกลุ่ม PK เดียว
   ✅ คิดให้ดี (date, status#date, category#price)

⑧ GSI ฟรี
   ❌ GSI คิด RCU/WCU แยก (จ่ายเพิ่ม)
   ✅ ใช้เท่าที่จำเป็น
```

---

# ส่วนที่ 8: คำสั่งที่ใช้บ่อย (AWS CLI)

```bash
# ดู table ทั้งหมด
aws dynamodb list-tables

# ดูรายละเอียด table (schema, index, capacity)
aws dynamodb describe-table --table-name shop

# ดู item
aws dynamodb get-item \
  --table-name shop \
  --key '{"PK":{"S":"USER#u001"},"SK":{"S":"PROFILE"}}'

# Query
aws dynamodb query \
  --table-name shop \
  --key-condition-expression "PK = :pk" \
  --expression-attribute-values '{":pk":{"S":"USER#u001"}}'

# Scan (เลี่ยง!)
aws dynamodb scan --table-name shop --max-items 10

# ดู index ที่มี
aws dynamodb describe-table --table-name shop \
  --query 'Table.GlobalSecondaryIndexes[].IndexName'
```

---

# สรุปสั้น

```
PRIMARY KEY:
  Partition Key        → unique, ตัดสิน shard ★ ต้องกระจาย
  Partition + Sort Key → คุมความยืดหยุ่นของ query ★ ใช้บ่อย

PARTITION KEY:
  ✅ กระจายเยอะ (user_id, uuid)
  ❌ ค่าไม่กี่แบบ (status, category, date)
  แก้: เติม suffix (date#1, date#2 ...)

SORT KEY:
  ให้: เรียง, ช่วง, begins_with
  composite: status#date (ลำดับสำคัญ)

INDEX:
  GSI → PK ต่างได้, เพิ่มทีหลังได้, 20 ตัว, eventual
  LSI → PK เหมือน table, ★ ตอนสร้างเท่านั้น, 5 ตัว, strong ได้

QUERY API:
  GetItem  → เร็วสุด (PK เดียว)
  Query    → ใช้ key ★ แนะนำ
  Scan     → ❌ เลี่ยง (ช้า + แพง)

ออกแบบ: Query-first (รู้อะไรจะถาม → ออกแบบให้ตอบ)
```

---

## ไฟล์ที่เกี่ยวข้อง

```
why-dynamodb.md           ← ทำไมต้องใช้
dynamodb-data-types.md    ← data types
dynamodb-query-reference.md ← Query/Scan/Update (กำลังเขียน)
```
