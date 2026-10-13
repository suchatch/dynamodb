# DynamoDB vs OpenSearch — เลือกอะไร เมื่อไหร่

> เทียบ 2 เครื่องมือที่พบบ่อยในระบบเดียวกัน — ใช้คนละหน้าที่ ไม่ใช่แทนกัน
> เขียนสำหรับคนสาย SQL/MongoDB
> ตัวอย่าง generic (e-commerce)

---

# 1. สรุปสั้น — ทำคนละงาน

```
DynamoDB    =  "ตู้เซฟ + ดัชนี lookup"    → เก็บ + ดึงข้อมูลด้วย key
OpenSearch  =  "ป้ายบอกทาง + เครื่องค้นหา" → ค้นหาข้อความ + วิเคราะห์

★ ไม่ใช่ "อันไหนดีกว่า" — แต่คือ "อันไหนเหมาะกับงานไหน"
★ ในระบบจริง มักใช้ "ทั้งคู่" (DynamoDB เป็นหลัก + OpenSearch สำหรับ search)
```

**ตารางเปรียบเทียบเดียว:**

| | DynamoDB | OpenSearch |
|---|---|---|
| จุดแข็ง | key-value lookup, transactional | full-text search, analytics |
| Query | GetItem/Query (ตาม key) | DSL ยืดหยุ่น (ค้นอะไรก็ได้) |
| Query-first? | ★ ต้องรู้อะไรจะถามก่อน | ✗ ยืดหยุ่น — query ทีหลังได้ |
| Schema | ต้อง declare key | mapping (แก้ไม่ได้แต่ยืดหยุ่นกว่า) |
| Consistency | strong / eventual | eventual (~1 วินาที) |
| Transaction | ✅ TransactWriteItems | ❌ |
| JOIN | ❌ | ❌ |
| Aggregation | ❌ pre-aggregate | ✅ aggs ในตัว |
| Full-text | ❌ | ✅ |
| Scale | auto (managed) | ตั้งเอง (shard/replica) |
| Latency | single-digit ms | ms (10s-100s) |
| ราคา | ตาม usage | ตาม node/ชั่วโมง |

---

# 2. เทียบตามงาน (ตัวตัดสินใจหลัก)

| งาน | DynamoDB | OpenSearch | หมายเหตุ |
|---|:---:|:---:|---|
| ดูข้อมูลด้วย id | ✅ | ~ | DynamoDB เร็วกว่า |
| ดูรายการของ user | ✅ | ~ | DynamoDB (Query) |
| **ค้นหาข้อความ** | ❌ | ✅ | OpenSearch ชัดเจน |
| ค้นหาตัวพิมพ์เล็ก/ใหญ่ | ❌ | ✅ | text + analyzer |
| **facet / filter หลายมิติ** | ❌ | ✅ | aggs |
| **จัดอันดับ (relevance)** | ❌ | ✅ | BM25 |
| autocomplete / suggest | ❌ | ✅ | match_phrase_prefix |
| analytics / dashboard | ❌ | ✅ | aggs + Visualize |
| log / time-series | ~ TTL | ✅ | OpenSearch เหมาะกว่า |
| **transaction** | ✅ | ❌ | DynamoDB ชัดเจน |
| atomic counter | ✅ | ❌ | DynamoDB |
| session / cart | ✅ | ~ | DynamoDB (ms) |
| เก็บรูป/ไฟล์ | ~ (≤400KB) | ❌ | ใช้ S3 |
| ข้อมูล > 1M แถว | ✅ | ✅ | ทั้งคู่ได้ (ต่างวิธี) |
| ต้องการ ad-hoc query | ❌ | ~ | DynamoDB ไม่ได้ |

**★ กฎง่ายๆ:**
```
"ดึงด้วย key ที่รู้"           → DynamoDB
"ค้นหาด้วยข้อความ/เงื่อนไข"    → OpenSearch
"ต้องการ transaction"         → DynamoDB
"ต้องการ aggregate/report"    → OpenSearch
```

---

# 3. สถาปัตยกรรมที่พบบ่อย — ใช้ทั้งคู่

## 3.1 Pattern: DynamoDB (source) + OpenSearch (search)

```
┌────────────────────────────────────────────┐
│  Application                                │
└───────┬────────────────────────┬────────────┘
        │ write                  │ search
        ↓                        ↓
┌───────────────────┐   ┌──────────────────────┐
│  DynamoDB         │   │  OpenSearch           │
│  (Source of Truth)│   │  (Search Index)       │
│  · transaction     │   │  · full-text          │
│  · ms latency      │   │  · facets             │
│  · scale           │   │  · ranking            │
└─────────┬─────────┘   └──────────▲───────────┘
          │                        │
          │  Streams → Lambda      │
          └────────────────────────┘
              (sync อัตโนมัติ)
```

**ขั้นตอน:**
```
① เขียนลง DynamoDB (source of truth)
② DynamoDB Streams จับการเปลี่ยนแปลง
③ Lambda อ่าน stream → เขียนลง OpenSearch
④ ค้นหา → query OpenSearch
```

**★ ข้อดี:**
```
✓ DynamoDB = ข้อมูลจริง (transaction, strong consistency)
✓ OpenSearch = search ที่ยืดหยุ่น (ไม่กระทบ DB หลัก)
✓ แยก workload
```

**⚠️ ข้อควรระวัง:**
```
✗ eventual consistency (OpenSearch อาจตามหลังเล็กน้อย)
✗ ต้องจัดการ error/resync (ถ้า Lambda ล้ม)
✗ ต้องดูค่าใช้จ่าย 2 ระบบ
```

## 3.2 Pattern: เมื่อไหร่ใช้ตัวเดียว

```
ใช้ DynamoDB อย่างเดียว เมื่อ:
  ✓ ไม่ต้อง full-text search
  ✓ query ทั้งหมดใช้ key ได้
  ✓ ไม่ต้อง facet/aggs

ใช้ OpenSearch อย่างเดียว เมื่อ:
  ✓ ไม่ต้อง transaction
  ✓ ยอมรับ eventual consistency
  ✓ ข้อมูลไม่ critical (log, analytics)
  ⚠️ ไม่แนะนำสำหรับ source of truth
```

---

# 4. เทียบ concept (แผนที่)

```
หัวข้อ               DynamoDB                 OpenSearch
───────────────────  ───────────────────────  ─────────────────────────
หน่วยเก็บ            Table / Item             Index / Document
Key                  PK (+ SK) — บังคับ        _id (optional)
ต้องรู้อะไรก่อน       ★ query ที่ต้องการ        ไม่ต้อง (ยืดหยุ่น)
เพิ่ม index ทีหลัง     GSI ได้ / LSI ไม่ได้      สร้าง index ใหม่ (reindex)
Schema               key เท่านั้น             mapping (แก้ไม่ได้)
Query ด้วยอะไร        ต้องเป็น key             อะไรก็ได้
กรอง                 FilterExpression (⚠️)     filter (มีประสิทธิภาพกว่า)
เรียง                 Sort Key                  sort (บน keyword)
Aggregate            ❌                        ✅ aggs
Search ข้อความ        ❌                        ✅
Transaction          ✅ (≤100 ops)             ❌
Consistency          strong/eventual           eventual (~1s)
Capacity             auto / provisioned        node (ตั้งเอง)
ราคา model           ตาม request              ตาม node/ชั่วโมง
```

**เทียบกับ SQL:**
```sql
-- DynamoDB ≈ SELECT ... WHERE pk = x (key lookup เท่านั้น)
-- OpenSearch ≈ SELECT ... WHERE <อะไรก็ได้> + FULLTEXT + GROUP BY
```

---

# 5. เทียบราคา

## 5.1 DynamoDB

```
On-Demand:
  Read   $0.25 / ล้าน reads
  Write  $1.25 / ล้าน writes
  Storage $0.25 / GB-เดือน

★ จ่ายตามที่ใช้จริง
★ Scan = แพง (อ่านเยอะ)
```

## 5.2 OpenSearch

```
AWS OpenSearch Service:
  node × ชั่วโมง (r7g.medium ≈ $0.10-0.15/hr)
  4 nodes × 24hr × 30d ≈ $300-450/เดือน
  + storage EBS

★ จ่ายตาม node (ไม่ว่ามี traffic ไหม)
★ ไม่มี traffic ให้ผลเท่ากัน = จ่ายเท่าเดิม
```

## 5.3 เมื่อไหร่ไหนถูกกว่า

| สถานการณ์ | ถูกกว่า |
|---|---|
| traffic น้อย / ไม่แน่นอน | **DynamoDB** (ตามใช้) |
| traffic มาก + คงที่ | ~ เท่ากัน / OpenSearch อาจถูกกว่า |
| ข้อมูลเยอะ + query เยอะ | DynamoDB (ถ้าใช้ key) |
| ต้องการ search + facet | OpenSearch (จำเป็น) |
| ต้องเก็บ log ปริมาณมาก 24/7 | ~ พิจารณา (OpenSearch node คงที่) |

**★ ข้อคิด:**
```
DynamoDB: ยิ่งใช้ยิ่งจ่าย (แต่ไม่ใช้ = ไม่จ่าย)
OpenSearch: จ่ายตลอด (มี server ทิ้ง)

→ ไม่รู้ traffic → DynamoDB ปลอดภัยกว่าเรื่องงบ
→ ต้อง search → OpenSearch จำเป็น (ไม่ใช่เรื่องเลือก)
```

---

# 6. ★ เมื่อไหร่ใช้ "ตัวไหน" — ตารางตัดสินใจ

```
คำถาม                                              → เลือก
─────────────────────────────────────────────────  ────────────────────
ต้อง full-text search ไหม?                          ใช่ → OpenSearch
                                                    ไม่ → DynamoDB ได้

ต้อง facet / aggregate / dashboard ไหม?              ใช่ → OpenSearch
                                                    ไม่ → DynamoDB

ต้อง transaction (atomic หลาย operation) ไหม?       ใช่ → DynamoDB
                                                    ไม่ → พิจารณา

รู้ query ล่วงหน้าชัดเจนไหม?                          ใช่ → DynamoDB
                                                    ไม่ → OpenSearch

ต้องการ latency < 10ms + scale?                     ใช่ → DynamoDB
ใช้ serverless (Lambda) เป็นหลัก?                   ใช่ → DynamoDB
ต้องการ ad-hoc query / analyst ใช้?                 ใช่ → ❌ DynamoDB
```

## 6.1 ตัวอย่างจริง

```
✓ E-commerce product search     → OpenSearch (search + facet)
✓ E-commerce cart/session       → DynamoDB (ms, transaction)
✓ User profile lookup           → DynamoDB
✓ Order history ของ user        → DynamoDB (Query by user_id)
✓ "ค้นหาสินค้า 'iphone' ตัวเล็ก" → OpenSearch
✓ นับสินค้าตามหมวด              → OpenSearch (aggs)
✓ นับโพสต์ของ user              → DynamoDB (counter)
✓ Log รวม                       → OpenSearch
✓ ระบบโอนเงิน                   → DynamoDB (TransactWrite)
```

## 6.2 ระบบที่ใช้ทั้งคู่ (ตัวอย่าง)

```
E-commerce:
  DynamoDB:
    - users, orders, cart, inventory
    - transaction (จองสต็อก)
    - session
    
  OpenSearch:
    - product search (title, description)
    - facet (brand, category, price range)
    - autocomplete
    - analytics dashboard
    
  Sync: DynamoDB Streams → Lambda → OpenSearch
```

---

# 7. กับดักเมื่อใช้คู่กัน

```
① คิดว่า OpenSearch = source of truth
   ❌ OpenSearch เป็น read model → สร้างใหม่ได้จาก DynamoDB
   ✅ DynamoDB = จริง, OpenSearch = สำเนา

② sync ไม่ครบ → ข้อมูลไม่ตรงกัน
   ✅ จัดการ error ใน Lambda (retry, DLQ)
   ✅ มี full reindex สำหรับกู้คืน

③ ค้นหาแล้วไม่เจอข้อมูลใหม่ (delay)
   ✅ ยอมรับ eventual consistency
   ✅ หรืออ่าน DynamoDB ก่อน (ถ้าต้องการแม่นยำ)

④ เก็บข้อมูลซ้ำ 2 ที่ → เปลือง
   ✅ เก็บเฉพาะ field ที่ต้อง search ใน OpenSearch

⑤ ลืม reindex เมื่อเปลี่ยน mapping
   ✅ วางแผน: สร้าง index ใหม่ + reindex + สลับ alias

⑥ ใช้ DynamoDB สำหรับ search → Scan แพง
   ✅ ใช้ OpenSearch

⑦ ใช้ OpenSearch สำหรับ transaction → ไม่มี
   ✅ ใช้ DynamoDB

⑧ งบบานปลาย (2 ระบบ)
   ✅ คำนวณล่วงหน้า (OpenSearch node คงที่ + DynamoDB ตามใช้)
```

---

# 8. เทียบกับเครื่องมืออื่น (ภาพรวม)

| เครื่องมือ | บทบาท | Query | ใช้กับ |
|---|---|---|---|
| **DynamoDB** | key-value, transactional | ตาม key | ข้อมูลหลัก, ms, scale |
| **OpenSearch** | search + analytics | ยืดหยุ่น | full-text, facet, report |
| RDS/Aurora | relational | SQL เต็ม | JOIN, transaction ซับซ้อน |
| ElastiCache (Redis) | cache | key | cache, session (เร็วกว่า Dynamo) |
| S3 | object storage | ❌ | ไฟล์, archive, data lake |
| Redshift/Athena | analytics | SQL | report จาก data lake |

**เลือกตามงาน:**
```
ต้องการ JOIN + SQL เต็ม     → RDS/Aurora
ต้องการ key lookup + ms    → DynamoDB
ต้องการ search + facet     → OpenSearch
ต้องการ cache               → Redis/ElastiCache
ต้องการเก็บไฟล์            → S3
ต้องการ analytics จากไฟล์   → Athena/Redshift
```

---

# 9. สรุปสุดท้าย

```
DynamoDB ≠ OpenSearch
→ ต่างคนต่างเก่ง (complementary)

DynamoDB:
  ✓ เก็บ + ดึงด้วย key
  ✓ transaction, ms, scale
  ✓ ราคาตามใช้
  ✗ ไม่มี search / aggregate

OpenSearch:
  ✓ search, facet, analytics
  ✓ query ยืดหยุ่น
  ✗ ไม่มี transaction
  ✗ จ่ายตาม node (ตลอด)

ระบบจริง:
  ★ DynamoDB = source of truth
  ★ OpenSearch = search index (sync ผ่าน Streams)
  ★ ใช้คู่กัน = ได้ทั้ง transaction + search
```

**ตัดสินใจเร็ว:**
```
"ดึงด้วย key"        → DynamoDB
"ค้นหาด้วยข้อความ"    → OpenSearch
"ต้องทั้งคู่"          → ใช้ทั้งคู่ (DynamoDB + Streams + OpenSearch)
```

---

## ไฟล์ที่เกี่ยวข้อง

```
why-dynamodb.md               ทำไมต้อง DynamoDB
dynamodb-key-design.md        ออกแบบ key
dynamodb-best-practices.md    แนวปฏิบัติที่ดี
```
