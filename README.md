# DynamoDB — เรียนและอ้างอิง (สำหรับ Dev สาย MySQL/MongoDB)

เอกสารภาษาไทยสำหรับเรียน **Amazon DynamoDB** — เขียนสำหรับคนที่ถนัด SQL/MongoDB
ทุก concept เทียบกับสิ่งที่คุ้นเคย พร้อมกับดักที่คนจาก SQL มักเจอ

> ⚠️ **หมายเหตุ:** เอกสารชุดนี้เป็น **ทฤษฎี/reference** (ไม่มี setup, ไม่มี credential)
> ตัวอย่างทั้งหมดเป็น generic (e-commerce) ไม่มีข้อมูลองค์กร

---

## เริ่มอ่านจากไหน

| ลำดับ | ไฟล์ | เนื้อหา |
|---|---|---|
| 1 | **`why-dynamodb.md`** | ทำไมต้องใช้ — เทียบ SQL/MongoDB, decision matrix, ต้นทุน |
| 2 | **`dynamodb-key-design.md`** | ★ หัวใจ — Partition Key, Sort Key, GSI, LSI |
| 3 | **`dynamodb-data-types.md`** | types ทั้งหมด (S/N/B/BOOL/L/M/SS...) |
| 4 | **`dynamodb-query-reference.md`** | API + 🔴 สิ่งที่ทำให้แพง/ช้า |
| 5 | **`dynamodb-best-practices.md`** | แนวปฏิบัติที่ดี (key design, single-table, cost, security) |
| 6 | **`migration-from-sql.md`** | ย้ายจาก SQL/MongoDB (วิธีคิด + ตัวอย่างแปลงครบชุด) |
| 7 | **`dynamodb-vs-opensearch.md`** | เทียบกับ OpenSearch (เลือกอะไร เมื่อไหร่ + ใช้คู่กัน) |
| 8 | **`dynamodb-local-setup.md`** | 🔬 ทดลองของจริง — DynamoDB Local + 13 หัวข้อ |
| 9 | **`dynamodb-examples.md`** | โค้ดจริง (boto3 / Node.js) — CRUD, query, pagination, transaction |

> **มี script รันได้:** `scripts/setup-dynamodb-local.sh` · `scripts/demo-query-vs-scan.sh` · `scripts/cleanup-dynamodb-local.sh`

---

## สารบัญเอกสาร

### `why-dynamodb.md` (15 หัวข้อ)

```
1-3   DynamoDB คืออะไร + Query-first design + Primary Key
4-5   Query vs Scan + GSI/LSI
6-7   Data types + Capacity mode
8     Decision matrix (ควร/ไม่ควรใช้)
9     ต้นทุนที่แท้จริง
10    ทางเลือกอื่น (RDS, Mongo, Redis, OpenSearch...)
11    กับดัก 7 ข้อจากคนสาย SQL
12    mental model SQL → DynamoDB
13-15 สรุป + คำถามที่ควรถามกลับ + ลำดับการเรียนรู้
```

### `dynamodb-key-design.md` (8 ส่วน)

```
1     Primary Key (simple / composite)
2     ★ Partition Key — hot partition + วิธีแก้
3     Sort Key — composite key (status#date)
4     ★ GSI vs LSI (ตารางเทียบครบ)
5     Query API (GetItem / Query / Scan)
6     ★ Query-first design 5 ขั้น + single-table design
7     กับดัก key design 8 ข้อ
8     คำสั่ง AWS CLI
```

### `dynamodb-data-types.md` (10 ส่วน)

```
1-3   Scalar (S, N, B, BOOL, NULL)
4     Set types (SS, NS, BS) ★ พิเศษเฉพาะ DynamoDB
5     ตารางเทียบ type ครบ
6     ★ วันที่/เวลา — S (ISO) vs N (epoch)
7     กับดัก data types 8 ข้อ
8     ข้อจำกัด (item ≤ 400 KB)
9-10  ตัวอย่าง item ครบชุด + AWS CLI
```

### `dynamodb-query-reference.md` (8 ส่วน)

```
1-3   API อ่าน/เขียน + ตารางราคา
4     Expression (KeyCondition/Filter/Update/Condition)
5     🔴 สิ่งที่ทำให้แพง/ช้า — ห้ามทำบน prod
6     วิธีอ่านเยอะอย่างปลอดภัย (pagination, export S3, DAX, TTL)
7     ตารางเทียบ SQL → DynamoDB
8     คำสั่ง copy-paste
```

---

## สรุป 5 concept ที่ต้องเข้าใจ (สำหรับคนสาย SQL)

```
① Query-first design
   SQL: ออกแบบข้อมูลก่อน → query อะไรก็ได้
   DynamoDB: ★ รู้อะไรจะ query ก่อน → แล้วออกแบบ key

② Partition Key ตัดสิน shard
   ✅ กระจายเยอะ (user_id, uuid)
   ❌ ค่าไม่กี่แบบ (status, category, date) → hot partition

③ Query vs Scan
   Query = ใช้ key (เร็ว, ถูก) ★
   Scan  = อ่านทั้ง table (ช้า, แพง — เลี่ยง)

④ Index ต้องวางแผนล่วงหน้า
   GSI → เพิ่มทีหลังได้
   LSI → ★ สร้างทีหลังไม่ได้เลย

⑤ ราคาตาม usage
   จ่ายตามข้อมูลที่ "อ่าน" → Scan = แพงทันที
   ตรวจได้: --return-consumed-capacity TOTAL
```

---

## ตารางเทียบเร็ว — SQL → DynamoDB

| SQL | DynamoDB |
|---|---|
| Database | (ไม่มี — AWS account) |
| Table | Table |
| Row | Item |
| Column | Attribute |
| `SELECT WHERE pk=x` | GetItem / Query |
| `SELECT WHERE other=z` | ★ GSI หรือ Scan |
| `INSERT` | PutItem |
| `UPDATE SET` | UpdateItem |
| `BEGIN...COMMIT` | TransactWriteItems |
| `JOIN` | ❌ denormalize |
| `GROUP BY` | ❌ pre-aggregate |
| `CREATE INDEX` ทีหลัง | GSI (ได้) / LSI (ไม่ได้) |
| `EXPLAIN` | `--return-consumed-capacity` |

---

## กับดัก 7 ข้อที่คนจาก SQL เจอบ่อย

```
① พยายาม JOIN → ทำไม่ได้ → denormalize
② ใช้ Scan เพราะ query ไม่ผ่าน key → ช้า + แพง
③ ใช้ status/category เป็น PK → hot partition
④ คิดว่า 1 table = 1 entity → single-table design
⑤ FilterExpression คิดว่าถูกกว่า Query → ❌ จ่ายเท่าเดิม
⑥ ลืมว่า LSI สร้างทีหลังไม่ได้
⑦ เก็บเงินเป็น float → เก็บ integer (สตางค์)
```

---

## ข้อจำกัดที่ต้องรู้

```
Item size        ≤ 400 KB ★
Number precision  38 digits
Nested depth      32 levels
GSI               20 ตัว/table
LSI               5 ตัว/table (สร้างทีหลังไม่ได้)
TransactWrite     ≤ 100 operations
Query/Scan คืน     ≤ 1 MB ต่อครั้ง (ใช้ pagination)
```

---

## ไฟล์ในโปรเจกต์

```
why-dynamodb.md               ทำไมต้องใช้ (decision + ต้นทุน)
dynamodb-key-design.md        PK/SK/GSI/LSI + design
dynamodb-data-types.md        types ทั้งหมด
dynamodb-query-reference.md   API + prod safety
dynamodb-best-practices.md    แนวปฏิบัติที่ดี (11 หมวด + checklist)
migration-from-sql.md         ย้ายจาก SQL/MongoDB (9 ส่วน + ตัวอย่าง)
dynamodb-vs-opensearch.md     เทียบ OpenSearch (9 ส่วน + ใช้คู่กัน)
dynamodb-local-setup.md       🔬 ทดลองของจริง (DynamoDB Local)
dynamodb-examples.md          โค้ดจริง boto3 / Node.js
scripts/
  setup-dynamodb-local.sh       ตั้ง Local + table + data + GSI
  demo-query-vs-scan.sh         สาธิต Query vs Scan (ตัวเลขจริง)
  cleanup-dynamodb-local.sh     ลบทั้งหมด
README.md                     ไฟล์นี้
```

---

## 🔬 ลองของจริง (DynamoDB Local)

```bash
./scripts/setup-dynamodb-local.sh    # ตั้ง Local + ข้อมูลตัวอย่าง
./scripts/demo-query-vs-scan.sh      # พิสูจน์ Query vs Scan (ตัวเลขจริง)
./scripts/cleanup-dynamodb-local.sh  # ลบทั้งหมด
```

ผลที่ได้ (ตัวอย่าง):
```
Query + Filter  → Scanned 4  ← ★ Filter ไม่ลดการอ่าน!
Scan  + Filter  → Scanned 6  ← ❌ อ่านทั้ง table
GSI Query       → Scanned 2  ← ★ ดีสุด
```

รายละเอียด: `dynamodb-local-setup.md`

---

## ลิงก์

- AWS DynamoDB Docs: https://docs.aws.amazon.com/dynamodb/
- Best Practices: https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html
- NoSQL Workbench (เครื่องมือออกแบบ): https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/workbench.html
- DynamoDB Local (ทดสอบในเครื่อง): https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/DynamoDBLocal.html
