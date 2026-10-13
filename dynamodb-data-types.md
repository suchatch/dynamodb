# DynamoDB Data Types — Reference

> Attribute types ทั้งหมด + วิธีใช้ + กับดัก
> เทียบกับ MySQL / MongoDB
> ตัวอย่าง generic (e-commerce)

---

# ส่วนที่ 1: ทำไม type ต้องระบุ

**ความต่างที่คนจาก SQL/MongoDB ต้องรู้:**

```
MySQL:      type มาจาก schema (column)
            INSERT INTO t VALUES ('Somchai', 42)   ← DB รู้ว่า column เป็นอะไร

MongoDB:    type มาจาก value (BSON)
            {name: "Somchai", age: 42}             ← 42 = NumberInt

DynamoDB:   ★ ต้องระบุ type ทุกค่า
            {"name": {"S": "Somchai"}, "age": {"N": "42"}}
                     ↑ ต้องบอกว่าคือ String
```

**เทียบให้เห็นภาพ:**
```json
// MongoDB (สั้น สบาย)
{"name": "Somchai", "age": 42, "active": true}

// DynamoDB (verbose ต้องระบุ type)
{
  "name":   {"S": "Somchai"},
  "age":    {"N": "42"},
  "active": {"BOOL": true}
}
```

**ทำไมต้องระบุ:**
```
DynamoDB เป็น schemaless แต่ type เก็บที่ "ค่าของแต่ละ attribute"
→ engine ต้องรู้ type เพื่อ index + compare
→ แลกกับ flexibility ที่ไม่มี schema
```

---

# ส่วนที่ 2: Scalar Types (ค่าเดียว)

## 2.1 `S` — String

```
{"S": "Somchai"}
{"S": "2026-10-13"}
{"S": "u001"}
{"S": ""}                   ← string ว่างได้
```

**เทียบ:**

| MySQL | MongoDB | DynamoDB |
|---|---|---|
| `VARCHAR(n)` | String | `S` |
| `TEXT` | String | `S` |
| `DATE` (เก็บเป็น string) | String | `S` |

**★ ใช้กับ:** ข้อความ, date (ISO format), id, enum values

```
✓ ใช้ S เก็บวันที่:  {"S": "2026-10-13T10:00:00Z"}
   → เรียงลำดับได้ (lexicographic = chronological ถ้า ISO 8601)
```

## 2.2 `N` — Number

```
{"N": "42"}
{"N": "3.14"}
{"N": "-100"}
{"N": "0"}
{"N": "1.5e10"}
```

**เทียบ:**

| MySQL | MongoDB | DynamoDB |
|---|---|---|
| `TINYINT/SMALLINT/INT/BIGINT` | NumberInt/Long | `N` (รวมหมด) |
| `FLOAT/DOUBLE` | NumberDouble | `N` |
| `DECIMAL(10,2)` | NumberDecimal | `N` ⚠️ |

**★ ข้อดี:** `N` รองรับความแม่นยำ 38 หลัก (เหมือน DECIMAL)

**⚠️★ กับดักสำคัญ:**
```
N เก็บเป็น string เสมอ (ต้อง quote!)
  {"N": "42"}   ← ✓
  {"N": 42}     ← ✗ (JSON parse ได้ แต่อาจมี issue)

★ เรื่องเงิน:
  ⚠️ ถ้าใช้ N กับทศนิยม → มี floating-point issue ในบาง operation

  ✅ แนะนำเก็บเงินเป็น integer (สตางค์/เซนต์)
     ราคา 459.00 บาท → {"N": "45900"}
     → คำนวณแม่นยำ 100%

  หรือถ้าใช้ทศนิยม → ระวังการบวก/ลบ/หาร
     (เหมือน MongoDB ที่แนะนำ NumberDecimal)
```

## 2.3 `B` — Binary

```
{"B": "<base64-encoded-bytes>"}
```

**เทียบ:**

| MySQL | MongoDB | DynamoDB |
|---|---|---|
| `BLOB` | Binary | `B` |

**★ ใช้กับ:** ไฟล์เล็ก, รูป thumbnail, hash, encryption key

```
⚠️ ไม่เหมาะกับไฟล์ใหญ่ (DynamoDB item จำกัด 400 KB)
   → ไฟล์ใหญ่: เก็บใน S3, เก็บ path ใน DynamoDB
```

## 2.4 `BOOL` — Boolean

```
{"BOOL": true}
{"BOOL": false}
```

**เทียบ:**

| MySQL | MongoDB | DynamoDB |
|---|---|---|
| `TINYINT(1)` / `BOOLEAN` | Boolean | `BOOL` |

**⚠️ กับดัก:**
```
DynamoDB ไม่ยอมให้ใช้ BOOL เป็น key!
  PK = {"BOOL": true}   ← ✗ error

→ ถ้าต้องใช้เป็น key → เก็บเป็น S ("true"/"false")
```

## 2.5 `NULL` — Null

```
{"NULL": true}
```

**เทียบ:**

| MySQL | MongoDB | DynamoDB |
|---|---|---|
| `NULL` | null | `NULL` |

**★ หมายเหตุ:** DynamoDB ไม่ index ค่า NULL
```
Item ที่ attribute = NULL → ยังอยู่ใน item แต่ไม่มีใน index
→ query ไม่เจอ (ยกเว้น scan)
```

---

# ส่วนที่ 3: Document Types (ซ้อนได้)

## 3.1 `L` — List (array)

```
{"L": [
  {"S": "red"},
  {"S": "blue"},
  {"S": "black"}
]}
```

**รายการซับซ้อน:**
```
{"L": [
  {"M": {"color": {"S": "red"}, "qty": {"N": "5"}}},
  {"M": {"color": {"S": "blue"}, "qty": {"N": "3"}}}
]}
```

**เทียบ:**

| MySQL | MongoDB | DynamoDB |
|---|---|---|
| JSON column | Array | `L` |
| (join table) | Array of docs | `L` of `M` |

**★ ใช้กับ:** tags, ตัวเลือก, ประวัติ

**⚠️ กับดัก:**
```
① ลบ element กลาง list → ต้องเขียน list ใหม่ทั้งก้อน
   {"L": ["a","b","c"]} → ลบ "b" → {"L": ["a","c"]}   (เขียนทั้ง array)
   → ไม่ใช่ UPDATE แบบ position ได้ตรงๆ

② Query ใน list → ต้องใช้ GSI หรือ Scan
   (query บน element ใน list ทำได้จำกัด)

③ list ใหญ่ (1000s elements) → item ใหญ่ขึ้น → RCU/WCU แพง
   ★ item limit = 400 KB
```

## 3.2 `M` — Map (object)

```
{"M": {
  "name":  {"S": "Somchai"},
  "age":   {"N": "42"},
  "email": {"S": "user@example.com"}
}}
```

**ซ้อนได้:**
```
{"M": {
  "address": {"M": {
    "city":    {"S": "Bangkok"},
    "zip":     {"S": "10110"},
    "country": {"S": "TH"}
  }}
}}
```

**เทียบ:**

| MySQL | MongoDB | DynamoDB |
|---|---|---|
| JSON column | Embedded doc | `M` |

**★ ใช้กับ:** nested object, address, settings

**⚠️ กับดัก:**
```
① เข้าถึง nested → ใช้ path: "address.city"
   UpdateExpression: "SET address.city = :c"

② ขนาดนับรวม → item limit 400 KB

③ ⚠️★ Map attribute name ห้ามมีอักขระเหล่านี้:
   . (dot)   ← ★ ห้าม! (ใช้เป็น path separator)
   [ ]       ← ห้าม
   
   ตัวอย่างที่ผิด: {"M": {"user.name": {"S": "x"}}}   ← ✗
   
   ถ้าจำเป็นต้องมี → ใช้ ExpressionAttributeNames:
     UpdateExpression: "SET #n = :v"
     ExpressionAttributeNames: {"#n": "user.name"}   ← ✓
```

---

# ส่วนที่ 4: Set Types (★ พิเศษเฉพาะ DynamoDB)

**DynamoDB มี Set — MongoDB/MySQL ไม่มีแบบนี้**

## 4.1 `SS` — String Set

```
{"SS": ["red", "blue", "black"]}

★ คุณสมบัติ:
  - ไม่ซ้ำ (duplicate ถูกตัดทิ้งอัตโนมัติ)
  - ไม่เรียงลำดับ (unordered)
  - ต้องเป็น type เดียวกัน (string ทั้งหมด)
```

**เทียบ:

| MySQL | MongoDB | DynamoDB |
|---|---|---|
| (ไม่มี — ต้องใช้ join) | Array (ซ้ำได้) | `SS` (ไม่ซ้ำ) |
| `SET` type (MySQL มี แต่ต่างกัน) | — | `SS` |

**★ ใช้กับ:** tags, roles, permissions

**★ Operations พิเศษ (ทำได้เฉพาะ Set):**
```
① ADD — เพิ่มเข้า set
   UpdateExpression: "ADD tags :t"
   ExpressionAttributeValues: {":t": {"SS": ["green"]}}
   → ถ้ามีอยู่แล้ว = ไม่ทำอะไร (ไม่ error ไม่ซ้ำ)

② DELETE — ลบออกจาก set
   UpdateExpression: "DELETE tags :t"
   ExpressionAttributeValues: {":t": {"SS": ["blue"]}}

★ นี่คือจุดแข็งของ Set — เพิ่ม/ลบ element โดยไม่ต้องอ่านทั้งก้อน
   (ต่างจาก List ที่ต้องเขียนใหม่)
```

## 4.2 `NS` — Number Set

```
{"NS": ["1", "2", "3"]}
{"NS": ["3.14", "2.71"]}
```

**ใช้กับ:** ชุดตัวเลข (เช่น ระดับคะแนน, หมวดราคา)

## 4.3 `BS` — Binary Set

```
{"BS": ["<base64-1>", "<base64-2>"]}
```

## 4.4 ★ ตารางเทียบ List vs Set

| | `L` (List) | `SS`/`NS`/`BS` (Set) |
|---|---|---|
| ซ้ำได้ | ✅ | ❌ (ตัดทิ้ง) |
| เรียงลำดับ | ✅ (ตามที่ใส่) | ❌ (unordered) |
| เข้าถึง index | ✅ `list[0]` | ❌ |
| เพิ่ม element | ⚠️ เขียนทั้ง list | ✅ `ADD` (ง่าย!) |
| ลบ element | ⚠️ เขียนทั้ง list | ✅ `DELETE` (ง่าย!) |
| ความหมาย | เป็น list จริงๆ | เป็น "กลุ่มของค่า" |

**★ เลือกยังไง:**
```
ต้องการลำดับ + เข้าถึง index → L (List)
ต้องการแค่ "มี/ไม่มี" + เพิ่ม/ลบง่าย → SS (Set)
```

---

# ส่วนที่ 5: ตารางเทียบ Type ครบ

| MySQL | MongoDB | DynamoDB | หมายเหตุ |
|---|---|---|---|
| `VARCHAR(n)` | String | `S` | ข้อความ |
| `TEXT` | String | `S` | — |
| `TINYINT/SMALLINT/INT/BIGINT` | NumberInt/Long | `N` | รวมเป็น N |
| `FLOAT/DOUBLE` | NumberDouble | `N` | — |
| `DECIMAL(m,d)` | NumberDecimal | `N` | ★ ระวัง float |
| `BOOLEAN` | Boolean | `BOOL` | ใช้เป็น key ไม่ได้ |
| `BLOB` | Binary | `B` | ≤ 400 KB |
| `DATETIME` | Date | `S` (ISO) | ★ หรือ N (epoch) |
| `JSON` | Object | `M` | map |
| (array) | Array | `L` | list |
| (ไม่มี) | — | `SS`/`NS`/`BS` | ★ set ไม่ซ้ำ |
| `NULL` | null | `NULL` | ไม่ index |

---

# ส่วนที่ 6: วันที่/เวลา — วิธีเก็บ

**DynamoDB ไม่มี type `date`** ต้องเลือกวิธีเก็บเอง

## 6.1 เก็บเป็น `S` (ISO 8601) ★ แนะนำ

```
{"S": "2026-10-13T10:30:00Z"}
{"S": "2026-10-13"}
```

**ข้อดี:**
```
✓ อ่านออก ดูง่าย
✓ เรียงลำดับได้ (lexicographic = chronological)
✓ ใช้เป็น Sort Key ได้ → query ช่วงวันที่ได้ ★
✓ ไม่ต้องแปลงตอนแสดงผล
```

**ข้อเสีย:**
```
✗ กินพื้นที่มากกว่า number
✗ ต้อง format ให้ถูก (rewind: ต้อง ISO 8601 zero-padded)
   "2026-1-5"   ← ✗ เรียงผิด! ("2026-1-5" > "2026-10-01")
   "2026-01-05" ← ✓
```

## 6.2 เก็บเป็น `N` (epoch)

```
{"N": "1697184600"}        ← epoch seconds
{"N": "1697184600000"}     ← epoch millis
```

**ข้อดี:**
```
✓ ประหยัดพื้นที่
✓ เรียง/compare ได้ตรงๆ
✓ คำนวณได้ (บวก/ลบ)
```

**ข้อเสีย:**
```
✗ อ่านไม่ออก (ต้องแปลง)
✗ TTL ใช้ epoch seconds (ต่างหาก)
```

## 6.3 เก็บทั้งคู่ (hybrid)

```
{
  "created_at":        {"S": "2026-10-13T10:30:00Z"},   ← อ่านง่าย + sort key
  "created_at_epoch":  {"N": "1697184600"}              ← สำหรับคำนวณ
}
```

**★ เลือกยังไง:**

| ต้องการ | เก็บเป็น |
|---|---|
| อ่านง่าย + sort key | `S` (ISO 8601) |
| คำนวณ + ประหยัด | `N` (epoch) |
| ทั้งคู่ | เก็บ 2 field |

**⚠️ TTL ต้องเป็น `N` (epoch seconds) เท่านั้น**
```
TTL attribute: {"expire_at": {"N": "1697184600"}}
→ DynamoDB ลบ item อัตโนมัติเมื่อถึงเวลา
```

---

# ส่วนที่ 7: กับดัก data types

```
① N ต้องเป็น string
   {"N": 42}    ← ✗
   {"N": "42"}  ← ✓

② เก็บเงินเป็น float → ปัดเศษผิด
   ✅ เก็บ integer (สตางค์): {"N": "45900"}

③ BOOL ใช้เป็น key ไม่ได้
   ✅ เก็บเป็น S ("true"/"false")

④ Map key มี "." → error
   ✅ ใช้ ExpressionAttributeNames

⑤ วันที่ format ไม่ zero-padded → เรียงผิด
   "2026-1-5"   ← ✗
   "2026-01-05" ← ✓

⑥ ใช้ L (List) แทน SS (Set) → เพิ่ม/ลบยาก
   ✅ ถ้าไม่ต้องการลำดับ → ใช้ SS

⑦ ลบ NULL แล้ว item หาย?
   ❌ NULL ≠ ลบ attribute
   ✅ REMOVE attribute (ต่างกัน):
      REMOVE attr        → ลบ attribute จริงๆ
      SET attr = NULL    → set เป็นค่า null (attribute ยังอยู่)

⑧ เก็บไฟล์ใหญ่ใน item
   ❌ item limit = 400 KB
   ✅ ไฟล์ > 400 KB → เก็บใน S3
```

---

# ส่วนที่ 8: ข้อจำกัดที่ต้องรู้

```
① Item size limit        = 400 KB ★ (รวมทุก attribute)
② Attribute name length  = 64 KB
③ Nested depth           = 32 levels
④ List/Map size          = ไม่จำกัด (แต่รวมใน 400 KB)
⑤ Number precision       = 38 digits
⑥ Set                   = ไม่ซ้ำ, ไม่เรียง, ต้อง type เดียวกัน

★ 400 KB คือขีดจำกัดที่ต้องระวัง:
  - ไฟล์ → S3
  - log ยาวๆ → แยก item
  - list ใหญ่ → แยก item หรือใช้ GSI
```

---

# ส่วนที่ 9: ตัวอย่าง Item ครบชุด

```json
{
  "PK":         {"S": "USER#u001"},
  "SK":         {"S": "PROFILE"},
  "user_id":    {"S": "u001"},
  "name":       {"S": "Somchai Jaidee"},
  "email":      {"S": "user@example.com"},
  "age":        {"N": "32"},
  "balance":    {"N": "45900"},                       // ★ สตางค์ (459.00 บาท)
  "is_active":  {"BOOL": true},
  "roles":      {"SS": ["user", "premium"]},          // ★ set ไม่ซ้ำ
  "tags":       {"L": [                                // ★ list (มีลำดับ)
                   {"S": "vip"},
                   {"S": "bangkok"}
                 ]},
  "address":    {"M": {                                // ★ map
                   "city":    {"S": "Bangkok"},
                   "zip":     {"S": "10110"},
                   "country": {"S": "TH"}
                 }},
  "created_at": {"S": "2026-10-13T10:30:00Z"},        // ★ ISO (อ่านง่าย + sort)
  "updated_at": {"N": "1697184600"},                  // ★ epoch (คำนวณ)
  "expire_at":  {"N": "1728720600"},                  // ★ TTL (ต้องเป็น N)
  "avatar":     {"B": "iVBORw0KGgoAAAANS..."},        // binary (base64)
  "deleted_at": {"NULL": true}                        // null
}
```

---

# ส่วนที่ 10: วิธีเขียน/อ่าน (AWS CLI)

```bash
# เขียน item
aws dynamodb put-item --table-name shop --item '{
  "PK": {"S": "USER#u001"},
  "SK": {"S": "PROFILE"},
  "name": {"S": "Somchai"},
  "roles": {"SS": ["user", "admin"]}
}'

# อ่าน item
aws dynamodb get-item --table-name shop \
  --key '{"PK":{"S":"USER#u001"},"SK":{"S":"PROFILE"}}'

# ดู type ที่ได้ (output จะมี type กำกับ)
# {
#   "Item": {
#     "PK": {"S": "USER#u001"},
#     "roles": {"SS": ["user", "admin"]}
#   }
# }
```

---

# สรุปสั้น

```
SCALAR:
  S     ข้อความ, วันที่ ISO, id
  N     ตัวเลข (เก็บเป็น string!) — เงินใช้ integer
  B     binary (≤ 400 KB) — ไฟล์ใหญ่ไป S3
  BOOL  true/false — ใช้เป็น key ไม่ได้
  NULL  ค่า null — ไม่ index

DOCUMENT:
  L     list (มีลำดับ, ซ้ำได้) — เพิ่ม/ลบยาก
  M     map  (object) — key ห้ามมี "."

SET:
  SS/NS/BS — ไม่ซ้ำ, ไม่เรียง ★ เพิ่ม/ลบด้วย ADD/DELETE ง่าย

วันที่:
  S (ISO 8601)  → อ่านง่าย + sort key ★
  N (epoch)     → คำนวณ + TTL

Limit: item ≤ 400 KB ★
```

---

## ไฟล์ที่เกี่ยวข้อง

```
why-dynamodb.md            ← ทำไมต้องใช้
dynamodb-key-design.md     ← PK/SK/GSI/LSI
dynamodb-query-reference.md ← Query/Scan/Update
```
