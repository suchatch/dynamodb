# ทำไมต้อง DynamoDB — มุมมองจาก Dev สาย MySQL/MongoDB

> ตอบคำถาม: "ทำไมต้อง DynamoDB? ต่างจาก MySQL/MongoDB ยังไง? เมื่อไหร่ควร/ไม่ควรใช้?"
> เขียนสำหรับคนที่ถนัด SQL/MongoDB — จะอธิบายว่า DynamoDB ไม่ได้ "ดีกว่า" แต่ "แลกคนละอย่าง"

---

## 1. DynamoDB คืออะไร (นิยามสั้น)

```
DynamoDB = NoSQL (key-value + document) แบบ managed ของ AWS
         · scale อัตโนมัติ (ไม่ต้อง shard เอง)
         · latency ระดับ single-digit ms
         · จ่ายตาม usage (ไม่ต้องเปิด server ทิ้ง)
         · ★ แต่ query ได้จำกัดมาก — ต้องออกแบบก่อน
```

**ตารางเทียบ 3 ตัว:**

| | MySQL | MongoDB | DynamoDB |
|---|---|---|---|
| ชนิด | Relational | Document NoSQL | Key-Value + Document |
| Schema | ต้องประกาศ | ยืดหยุ่น | ไม่ต้อง แต่ key เข้ม |
| **Query** | SQL ยืดหยุ่น | `find()` ยืดหยุ่น | **★ จำกัดมาก** |
| Scale | vertical (เพิ่มเครื่อง) | sharding (ตั้งเอง) | **auto horizontal** |
| Managed | ดูแลเอง | ดูแลเอง | **AWS ดูแล** |
| Latency | ms | ms | **single-digit ms** |
| ราคา | เครื่อง/เดือน | เครื่อง/เดือน | **ตาม usage** |
| JOIN | ✅ | ~ `$lookup` | **❌ ไม่มี** |
| Transaction | ✅ เต็ม | ~ | ~ จำกัด (transact) |

---

## 2. ★ ความต่างที่ใหญ่ที่สุด — "Query-first design"

**นี่คือหัวใจที่คนจาก SQL/MongoDB พลาดบ่อยที่สุด**

```
MySQL / MongoDB:
  ออกแบบข้อมูลก่อน  →  แล้วค่อย query อะไรก็ได้ (ยืดหยุ่น)

DynamoDB:
  ★ ต้องรู้ "จะ query อะไร" ก่อน  →  แล้วออกแบบ key ให้ตอบ query นั้น
```

**ตัวอย่างจริง:**

```
โจทย์: ระบบออเดอร์ ต้องดู
  ① ออเดอร์ของ user คนนี้
  ② ออเดอร์ของ user นี้ ในช่วงวันที่นี้
  ③ ออเดอร์ทั้งหมดของวันนี้
  ④ ออเดอร์ที่ยังไม่จ่าย

MySQL:    ออกแบบ table 1 ตัว → query ได้ทั้ง 4 แบบ (ด้วย index ที่เพิ่มทีหลัง)
MongoDB:  ออกแบบ collection → สร้าง index ทีหลังได้
DynamoDB: ★ ต้องออกแบบ key + index ให้ครบ "ตั้งแต่วันแรก"
          ถ้าลืมแบบ ④ → เพิ่มทีหลังยากมาก (หรือทำไม่ได้)
```

**เทียบ:**

| | ออกแบบเมื่อไหร่ | เพิ่ม query ใหม่ทีหลัง |
|---|---|---|
| MySQL | ตอนสร้าง table | `CREATE INDEX` ทีหลังได้ |
| MongoDB | ตอนสร้าง collection | `createIndex` ทีหลังได้ |
| **DynamoDB** | **ตอนสร้าง table + index** | **★ ต้องสร้าง index ใหม่ (ถูกจำกัด)** |

★ **นี่คือข้อแลกเปลี่ยนหลัก:** DynamoDB ให้ scale/ความเร็ว แลกกับ **ความยืดหยุ่นของ query**

---

## 3. Primary Key — หัวใจของทุกอย่าง

### 3.1 Partition Key (ต้อง unique ถ้าไม่มี sort key)

```
┌───────────────────────────────┐
│ Partition Key                 │
├───────────────────────────────┤
│ user_id = "u001" → {name, ...}│
│ user_id = "u002" → {name, ...}│
└───────────────────────────────┘

เทียบ MySQL: PRIMARY KEY (user_id)
```

### 3.2 Partition Key + Sort Key ★ (ใช้บ่อยสุด)

```
┌──────────────────┬──────────────────────┐
│ Partition Key    │ Sort Key             │
├──────────────────┼──────────────────────┤
│ user_id = "u001" │ ts = "2026-10-01"    │
│ user_id = "u001" │ ts = "2026-10-05"    │  ← PK ซ้ำได้
│ user_id = "u001" │ ts = "2026-10-12"    │  ← แต่ PK+SK ห้ามซ้ำ
│ user_id = "u002" │ ts = "2026-10-03"    │
└──────────────────┴──────────────────────┘

เทียบ MySQL: PRIMARY KEY (user_id, ts)
เทียบ MongoDB: { _id: { user_id, ts } } หรือ compound index
```

### 3.3 ★★★ Partition Key = ตัวตัดสินว่าไป shard ไหน

```
PK = "u001"  → shard A
PK = "u002"  → shard B      (AWS กระจายให้อัตโนมัติ)
PK = "u003"  → shard A

★ ถ้า PK ไม่กระจาย → ทุกอย่างไป shard เดียว → ช้า!
   เช่นใช้ status = "active" เป็น PK
   → สินค้า active ทุกตัวไป shard เดียว → "hot partition"
```

**เทียบ MongoDB sharding:**
```
MongoDB: เลือก shard key เอง (ถ้าผิด → ต้อง re-shard = เจ็บ)
DynamoDB: AWS กระจายให้ → แต่ถ้า PK ผิด → hot partition (AWS ไม่แก้ให้)
          ★ AWS ช่วย scale แต่ไม่ช่วยถ้า key ออกแบบผิด
```

---

## 4. ★ Query vs Scan — หัวใจเรื่อง Performance

### 4.1 Query (เร็ว — ต้องใช้ key)

```
Query = ค้นหาด้วย Partition Key (+ filter ด้วย Sort Key)

GET ออเดอร์ของ user u001 ทั้งหมด:
  Query: PK = "u001"
  
GET ออเดอร์ของ user u001 เดือน ต.ค.:
  Query: PK = "u001" AND SK BETWEEN "2026-10-01" AND "2026-10-31"
```

**เร็ว:** เพราะรู้ว่าไป shard ไหนตรงๆ → latency ms คงที่

### 4.2 Scan (ช้า — อ่านทั้ง table)

```
Scan = อ่านทุก item ใน table แล้วค่อยกรอง

GET ออเดอร์ที่ status = "pending":
  ถ้า status ไม่ใช่ key → ต้อง Scan ทั้ง table
  → อ่าน 1 ล้าน items เพื่อหา 100 items ที่ต้องการ ★ ช้า + แพง!
```

**เทียบ:**

| | MySQL | DynamoDB |
|---|---|---|
| `WHERE id = 1` | index → เร็ว | **Query** → เร็ว |
| `WHERE status = 'x'` | index → เร็ว | ★ **Scan** → ช้า! (ถ้าไม่ทำ index) |
| `WHERE a=1 AND b=2` | index → เร็ว | ต้องมี key ตรง หรือ GSI |

**★ กฎ:** ถ้า query ไม่ได้ทำผ่าน key → Scan → **ช้าและแพง** (จ่ายตามข้อมูลที่อ่าน)

```
ค่าใช้จ่าย: DynamoDB คิดตาม RCU (Read Capacity Unit)
  Query 10 items   → จ่าย 10 items
  Scan 1M items    → ★ จ่าย 1M items! (แพงกว่า 100,000 เท่า)
```

### 4.3 วิธีแก้ — Secondary Index (GSI/LSI)

```
ถ้าต้อง query ด้วย status:
  → สร้าง GSI ที่ใช้ status เป็น partition key
  
⚠️ แต่: GSI ต้องสร้าง "ตอนสร้าง table" หรือเพิ่มทีหลัง (ทำได้ แต่มีข้อจำกัด)
```

---

## 5. Index — GSI vs LSI

| | GSI (Global Secondary Index) | LSI (Local Secondary Index) |
|---|---|---|
| Partition Key | **ต่างจาก table** ได้ | ต้องเหมือน table |
| Sort Key | ต่างได้ | ต่างได้ |
| สร้างเมื่อไหร่ | ตอนสร้าง หรือ **เพิ่มทีหลังได้** | ★ **ตอนสร้าง table เท่านั้น** |
| จำนวน | 20 ตัว | 5 ตัว |
| ขนาด | ไม่จำกัด | ≤ 10 GB ต่อ partition |
| Consistency | eventual | strong ได้ |

**เทียบ:**
```
MySQL:     CREATE INDEX หลังสร้าง table ได้ (ง่าย)
MongoDB:   createIndex ทีหลังได้ (ง่าย)
DynamoDB:  GSI เพิ่มทีหลังได้ (แต่ช้า + จำกัด)
           ★ LSI เพิ่มทีหลังไม่ได้เลย!
```

**★ นี่คือเหตุผลว่าทำไมต้องออกแบบให้ดีตั้งแต่แรก**

---

## 6. Data Types

```
DynamoDB ต้องระบุ type ทุกค่า (ต่างจาก MySQL/MongoDB):

"S"      String          {"S": "Somchai"}
"N"      Number          {"N": "42"}
"B"      Binary          {"B": "base64..."}
"BOOL"   Boolean         {"BOOL": true}
"NULL"   Null            {"NULL": true}
"L"      List            {"L": [{"S": "a"}, {"N": "1"}]}
"M"      Map             {"M": {"key": {"S": "value"}}}
"SS"     String Set      {"SS": ["a", "b", "c"]}      ← ★ set ไม่ซ้ำ
"NS"     Number Set      {"NS": ["1", "2", "3"]}
"BS"     Binary Set      {"BS": [...]}
```

**เทียบ:**

| MySQL | MongoDB | DynamoDB |
|---|---|---|
| VARCHAR | String | `S` |
| INT/BIGINT | NumberInt/Long | `N` (รวมหมด) |
| DECIMAL | NumberDecimal | `N` (ระวัง float) |
| BLOB | Binary | `B` |
| BOOLEAN | Boolean | `BOOL` |
| JSON | Object | `M` |
| (array) | Array | `L` หรือ `SS`/`NS` |
| NULL | null | `NULL` |

**⚠️ เรื่องเงิน:**
```
DynamoDB "N" = number ทั่วไป (มี floating-point issue)
→ ★ เก็บเงินควรเก็บเป็น string หรือ integer (สตางค์)
   เช่น "45900" แทน 459.00
   (เหมือน MongoDB ที่แนะนำ NumberDecimal)
```

---

## 7. Capacity Mode — ราคา/Performance

**2 โหมด:**

| | Provisioned | On-Demand |
|---|---|---|
| กำหนด | ตั้ง RCU/WCU ล่วงหน้า | ไม่ต้องตั้ง |
| ราคา | ถูกกว่า (ถ้าใช้สม่ำเสมอ) | แพงกว่า ~5-7x |
| Auto-scale | ตั้งได้ | อัตโนมัติ |
| เหมาะกับ | traffic คาดเดาได้ | traffic ขึ้นๆ ลงๆ / ไม่รู้ |
| เริ่มต้น | — | ★ แนะนำเริ่มจากนี้ |

```
RCU (Read Capacity Unit):
  1 RCU = อ่าน 4 KB (strong) หรือ 8 KB (eventual) ต่อวินาที

WCU (Write Capacity Unit):
  1 WCU = เขียน 1 KB ต่อวินาที
```

**เทียบ:**
```
MySQL:     จ่ายค่าเครื่อง fix (EC2 hours)
MongoDB:   จ่ายค่าเครื่อง fix หรือ Atlas units
DynamoDB:  ★ จ่ายตาม request + storage (ไม่มี server ทิ้ง)
```

---

## 8. Decision Matrix — เมื่อไหร่ควร / ไม่ควรใช้

### 8.1 ตามงาน

| งาน | MySQL | Mongo | DynamoDB |
|---|:---:|:---:|:---:|
| Transaction หนัก (bank, เงิน) | ✅ | ~ | ❌ |
| JOIN / relation ซับซ้อน | ✅ | ~ | ❌ |
| Ad-hoc query (ไม่รู้ล่วงหน้า) | ✅ | ✅ | ★ ❌ |
| Key-value lookup (ms) | ~ | ~ | ✅ |
| Session / cache / cart | ~ | ~ | ✅ |
| IoT / time-series (write เยอะ) | ✗ | ~ | ✅ |
| Serverless (Lambda) | ~ | ✗ | ★ ✅ |
| Scale ไม่จำกัด | ✗ | ~ | ✅ |
| ราคาต่ำตอน traffic น้อย | ~ | ✗ | ★ ✅ |

### 8.2 ★ ตารางตัดสินใจ

```
คำถาม                                        → เลือก
───────────────────────────────────────────  ─────────────────────
รู้ query ล่วงหน้าชัดเจนไหม?                   ใช่ → DynamoDB ได้
                                              ไม่ → MySQL/MongoDB

มี JOIN / relation ซับซ้อนไหม?                ใช่ → ❌ DynamoDB
                                              ไม่ → DynamoDB ได้

ต้องการ ad-hoc query (คนวิเคราะห์) ไหม?       ใช่ → ❌ DynamoDB
                                              ไม่ → DynamoDB ได้

traffic ขึ้นๆ ลงๆ + อยากจ่ายตามใช้?           ใช่ → ✅ DynamoDB
                                              ไม่ → DB ก็ได้

serverless (Lambda/Fargate) เป็นหลัก?        ใช่ → ★ DynamoDB
ต้องการ latency < 10ms ที่ scale มาก?          ใช่ → ★ DynamoDB
```

### 8.3 เมื่อไหร่ "ไม่ควร" ใช้ DynamoDB

```
❌ ต้องการ JOIN / relation หลายตาราง
❌ ต้องการ ad-hoc query / รายงานที่ query ไม่รู้ล่วงหน้า
❌ งานรายงานการเงิน/บัญชี (ต้อง aggregate ซับซ้อน)
❌ ทีมยังไม่เข้าใจ key design (จะได้ hot partition + scan แพง)
❌ ข้อมูลน้อย (< 1000 rows) → ไม่คุ้มความซับซ้อน
❌ ต้องการ full-text search → ใช้ OpenSearch แทน
❌ ต้องการ SQL ที่ยืดหยุ่น → ใช้ Aurora/RDS
```

---

## 9. ต้นทุนที่แท้จริง

### 9.1 เงิน

```
On-Demand (แนะนำเริ่ม):
  Read:  $0.25 ต่อ 1 ล้าน reads
  Write: $1.25 ต่อ 1 ล้าน writes
  Storage: $0.25 ต่อ GB/เดือน

Provisioned:
  RCU: ~$0.00013/ชม. ต่อ unit
  WCU: ~$0.00065/ชม. ต่อ unit
```

**⚠️ Scan แพงมาก:**
```
Scan 1M items:
  → จ่ายค่าอ่าน 1M items ทุกครั้งที่ scan!
  → ถ้า scan ทุกวัน = 30M reads/เดือน = ★ $7.50/เดือน ต่อ scan 1 ครั้ง/วัน
  
เทียบ Query: อ่านเฉพาะที่ match → ถูกกว่า 100-1000 เท่า
```

### 9.2 ต้นทุนที่มองไม่เห็น

| ด้าน | สิ่งที่เพิ่ม | ผลจริง |
|---|---|---|
| **Skill** | ต้องเข้าใจ key design | ★ โค้งเรียนสูง (ไม่เหมือน SQL) |
| **Design** | ต้องออกแบบ key ก่อนเขียนโค้ด | ทำผิด = ทำใหม่ (migrate เจ็บ) |
| **Query** | ทำได้จำกัด | Ad-hoc analysis ต้อง export |
| **Debug** | ไม่มี SQL console | ต้องใช้ AWS Console / CLI / NoSQL Workbench |
| **Vendor lock** | ผูกกับ AWS | ย้าย provider ยาก |
| **Index** | GSI/LSI มีข้อจำกัด | เพิ่มทีหลังเจ็บ |

**★ ต้นทุนที่แท้จริง = ต้องเปลี่ยนวิธีคิด**
```
จาก: "ออกแบบ schema → query อะไรก็ได้"
เป็น: "รู้อะไรจะ query → ออกแบบให้ตอบได้"
→ นี่คือ mental shift ที่ยากที่สุด
```

---

## 10. ทางเลือกอื่น — ทำไมไม่ใช้เจ้านั้น

| ทางเลือก | ข้อดี | ข้อเสีย | เหมาะกับ |
|---|---|---|---|
| **RDS / Aurora (MySQL/PG)** | SQL ยืดหยุ่น, managed | scale จำกัดกว่า, จ่ายเครื่อง | งาน relation, ad-hoc |
| **MongoDB Atlas** | flexible schema, query ยืดหยุ่น | จ่ายเครื่อง, shard ต้องตั้ง | งาน document ทั่วไป |
| **ElastiCache (Redis)** | เร็วมาก (sub-ms) | ไม่ durable, RAM แพง | cache, session |
| **OpenSearch** | full-text, facet, aggs | ไม่เหมาะ transactional | search / analytics |
| **ScyllaDB / Cassandra** | scale มาก, open source | ดูแลเองยาก | งาน scale มหาศาล |
| **DynamoDB** ⭐ | managed, auto-scale, ms | query จำกัด, lock-in | key-value ที่ query รู้ล่วงหน้า |

**ทำไมเลือก DynamoDB (บริบทธุรกิจ):**
```
① Managed เต็มตัว — ไม่มี server ให้ดูแล
② Auto-scale — รับ traffic พุ่งได้ทันที
③ จ่ายตามใช้ — ตอน traffic น้อยจ่ายน้อย
④ ผูกกับ Lambda/serverless ได้สวย
⑤ latency คงที่ (single-digit ms) แม้ข้อมูลโต
```

**เมื่อไหร่ควรใช้ตัวอื่น:**
```
ต้องการ SQL ยืดหยุ่น      → RDS / Aurora
ใช้ document ทั่วไป       → MongoDB
ต้องการ cache              → Redis / ElastiCache
ต้องการ full-text search  → OpenSearch
ต้องการ analytics/aggr     → Redshift / Athena / OpenSearch
```

---

## 11. กับดักที่พบบ่อย (จากคนสาย SQL)

```
① พยายาม JOIN → ทำไม่ได้
   → denormalize: ยัดข้อมูลที่ต้อง join ให้อยู่ใน item เดียว

② ใช้ Scan เพราะ query ไม่ได้ทำผ่าน key → ช้า + แพงมหาศาล
   → ออกแบบ key/GSI ตั้งแต่วันแรก

③ ออกแบบ PK ไม่กระจาย (เช่น status) → hot partition
   → เลือก PK ที่มีค่าเยอะและกระจาย (user_id, order_id)

④ คิดว่า 1 table = 1 entity (แบบ SQL)
   → DynamoDB: 1 table เก็บหลาย entity ได้
     (single-table design — pattern ที่นิยม)

⑤ คิดว่าข้อมูลน้อยๆ ก็ใช้ได้ → overkill
   → ถ้า < 1000 rows + query ง่าย → MySQL พอ

⑥ เพิ่ม index ทีหลัง → LSI ทำไม่ได้!
   → วางแผน index ตั้งแต่ออกแบบ

⑦ เก็บเงินเป็น "N" → floating-point error
   → เก็บเป็น string หรือ integer (สตางค์)
```

---

## 12. เปรียบเทียบ mental model — SQL → DynamoDB

```
SQL / MongoDB            DynamoDB                 ความต่างที่ต้องจำ
───────────────────────  ───────────────────────  ──────────────────────
Table / Collection       Table                    ★ key เข้ม (PK + SK)
Row / Document           Item                     —
Column / Field           Attribute                ★ type ทุกค่า (S/N/...)
SELECT ... WHERE         Query / Scan             ★ ต้องใช้ key
JOIN                     ❌                       ★ denormalize
CREATE INDEX ทีหลัง       GSI (ได้) / LSI (ไม่ได้)  ★ วางแผนล่วงหน้า
LIMIT                    Limit                     —
ORDER BY (sort key เท่านั้น) Sort Key (ใน Query)    —
COUNT(*)                 ⚠️ แพง (Scan + Count)     —
GROUP BY                 ❌ (ต้อง pre-aggregate)   —
Transaction              TransactWriteItems        ~ จำกัด (25 items)
Auto-increment           ❌ (ต้อง gen เอง)         —
```

---

## 13. สรุปสุดท้าย — ตอบคำถาม "ทำไม"

```
DynamoDB ไม่ได้ดีกว่า MySQL/MongoDB
→ แต่มันแลก "ความยืดหยุ่นของ query" กับ "scale + latency + managed"

  MySQL/MongoDB = ยืดหยุ่น (query อะไรก็ได้) แต่ต้องดูแล + scale เอง
  DynamoDB      = scale อัตโนมัติ + ms + managed แต่ ★ query จำกัด

เลือกใช้ตามงาน:
  รู้ query ล่วงหน้า + key-value + scale มาก  → DynamoDB
  ต้องการ relation / ad-hoc / รายงาน          → MySQL/Aurora/MongoDB
  ต้องการทั้งคู่                               → ใช้ทั้ง 2 (DynamoDB + RDS/OpenSearch)

★ ข้อแลกเปลี่ยน: DynamoDB แลก "ความยืดหยุ่น"
                 กับ "scale, latency, zero-ops"

★ ต้นทุนจริง: mental shift — "query-first design"
              (ต้องรู้อะไรจะถาม ก่อนออกแบบข้อมูล)
```

---

## 14. คำถามที่ควรถามกลับ (ก่อนตัดสินใจ)

```
① รู้ query ทั้งหมดล่วงหน้าไหม?
   → ถ้ารู้ → DynamoDB เขียน key design ได้
   → ถ้าไม่รู้ (ต้อง ad-hoc) → ใช้ DB อื่น

② ต้อง JOIN / relation ไหม?
   → ใช่ → ❌ DynamoDB
   → ไม่ → ได้

③ PK จะกระจายไหม? (ไม่ใช้ status/category เป็น PK)
   → ถ้าไม่กระจาย → hot partition → ต้องออกแบบใหม่

④ มี GSI/LSI ที่ต้องใช้ครบไหม? (วางแผนตั้งแต่วันแรก)
   → LSI เพิ่มทีหลังไม่ได้!

⑤ ทีมเข้าใจ key design ไหม?
   → ถ้าไม่ → ต้นทุนการเรียนรู้สูง → อาจใช้ RDS ก่อน
```

---

## 15. ลำดับการเรียนรู้ DynamoDB (สำหรับคนสาย SQL)

```
① โครงสร้าง (table/item/attribute)            ← ง่าย
② Primary Key (PK + SK)                     ← ★ หัวใจ
③ Query vs Scan                             ← ★ หัวใจ
④ Index (GSI / LSI)                          ← ยาก
⑤ Capacity mode + ราคา
⑥ Single-table design                        ← ขั้นสูง
⑦ TransactWriteItems / conditional write
⑧ Streams + Lambda integration
```

---

## ไฟล์ที่เกี่ยวข้อง

```
(ไฟล์นี้เป็นไฟล์แรกของ repo dynamodb)
- mapping/query reference        ← ยังไม่มี (สอนต่อได้)
- runbook (เหมือน P1/P2)          ← ยังไม่มี (ถ้ามีงานจริง)
```
