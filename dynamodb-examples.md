# DynamoDB Examples — โค้ดจริง (boto3 / Node.js)

> ตัวอย่างโค้ดที่ copy ไปใช้ได้ — Python (boto3) + Node.js (@aws-sdk)
> ทดสอบกับ DynamoDB Local ได้ (`dynamodb-local-setup.md`)
> ตัวอย่าง generic (e-commerce)

---

# ส่วนที่ 1: เชื่อมต่อ

## 1.1 Python (boto3)

### Local (ทดสอบ)
```python
import boto3

dynamodb = boto3.resource(
    'dynamodb',
    endpoint_url='http://localhost:8000',
    region_name='us-east-1',
    aws_access_key_id='dummy',       # ★ local ต้องมี (แต่ไม่ตรวจ)
    aws_secret_access_key='dummy',
)
table = dynamodb.Table('shop')
```

### Production (AWS)
```python
import boto3

# ใช้ credential จาก env / IAM role (ไม่ต้อง hardcode!)
dynamodb = boto3.resource('dynamodb', region_name='ap-southeast-1')
table = dynamodb.Table('shop')
```

**★ อย่า hardcode credential ในโค้ด:**
```
✅ ใช้ IAM role (Lambda/EC2/ECS)          ← ดีสุด (ไม่ต้องจัดการ key)
✅ ใช้ env var (AWS_ACCESS_KEY_ID, ...)
✅ ใช้ ~/.aws/credentials (dev เท่านั้น)
❌ hardcode ในโค้ด / commit ขึ้น git
```

### Client vs Resource

```python
# Resource (แนะนำ — ใช้ง่าย, pythonic)
table = dynamodb.Table('shop')
table.get_item(Key={'PK': 'CUST#u001', 'SK': 'PROFILE'})

# Client (low-level — ควบคุมได้มากกว่า)
client = boto3.client('dynamodb')
client.get_item(TableName='shop',
                Key={'PK': {'S': 'CUST#u001'}, 'SK': {'S': 'PROFILE'}})
```
**Resource** = ใส่ type อัตโนมัติ (`{'PK': 'CUST#u001'}`) / **Client** = ต้องระบุ type เอง

## 1.2 Node.js (@aws-sdk/client-dynamodb)

```javascript
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand } from "@aws-sdk/lib-dynamodb";

// Local
const client = new DynamoDBClient({
  endpoint: "http://localhost:8000",
  region: "us-east-1",
  credentials: { accessKeyId: "dummy", secretAccessKey: "dummy" },
});

// Production: new DynamoDBClient({ region: "ap-southeast-1" })

// DocumentClient = จัดการ type ให้ (เหมือน Resource ใน boto3)
const doc = DynamoDBDocumentClient.from(client);
```

**ติดตั้ง:**
```bash
npm install @aws-sdk/client-dynamodb @aws-sdk/lib-dynamodb
```

---

# ส่วนที่ 2: CRUD พื้นฐาน

## 2.1 Create / Put

### Python
```python
table.put_item(Item={
    'PK': 'CUST#u001',
    'SK': 'PROFILE',
    'name': 'Somchai',
    'email': 'user@example.com',
    'balance': 45900,
})

# สร้างใหม่เท่านั้น (ไม่ทับของเดิม)
from botocore.exceptions import ClientError

try:
    table.put_item(
        Item={'PK': 'CUST#u001', 'SK': 'PROFILE', 'name': 'Somchai'},
        ConditionExpression='attribute_not_exists(PK)',
    )
except ClientError as e:
    if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
        print("มีอยู่แล้ว")
```

### Node.js
```javascript
import { PutCommand } from "@aws-sdk/lib-dynamodb";

await doc.send(new PutCommand({
  TableName: "shop",
  Item: { PK: "CUST#u001", SK: "PROFILE", name: "Somchai", balance: 45900 },
}));

// สร้างใหม่เท่านั้น
try {
  await doc.send(new PutCommand({
    TableName: "shop",
    Item: { PK: "CUST#u001", SK: "PROFILE", name: "Somchai" },
    ConditionExpression: "attribute_not_exists(PK)",
  }));
} catch (e) {
  if (e.name === "ConditionalCheckFailedException") console.log("มีอยู่แล้ว");
}
```

## 2.2 Read / GetItem

### Python
```python
resp = table.get_item(
    Key={'PK': 'CUST#u001', 'SK': 'PROFILE'},
    ProjectionExpression='#n, balance',
    ExpressionAttributeNames={'#n': 'name'},
)
item = resp.get('Item')
if item:
    print(item['name'], item['balance'])
```

### Node.js
```javascript
import { GetCommand } from "@aws-sdk/lib-dynamodb";

const { Item } = await doc.send(new GetCommand({
  TableName: "shop",
  Key: { PK: "CUST#u001", SK: "PROFILE" },
  ProjectionExpression: "#n, balance",
  ExpressionAttributeNames: { "#n": "name" },
}));
```

## 2.3 Update

### Python
```python
# ตั้งค่า
table.update_item(
    Key={'PK': 'CUST#u001', 'SK': 'PROFILE'},
    UpdateExpression='SET #n = :name, updated_at = :ts',
    ExpressionAttributeNames={'#n': 'name'},
    ExpressionAttributeValues={
        ':name': 'Somchai J',
        ':ts': '2026-10-13T10:00:00Z',
    },
)

# atomic increment
table.update_item(
    Key={'PK': 'CUST#u001', 'SK': 'STATS'},
    UpdateExpression='ADD order_count :one',
    ExpressionAttributeValues={':one': 1},
)

# เพิ่มใน set
table.update_item(
    Key={'PK': 'CUST#u001', 'SK': 'PROFILE'},
    UpdateExpression='ADD roles :r',
    ExpressionAttributeValues={':r': {'premium'}},
)

# ลบ attribute
table.update_item(
    Key={'PK': 'CUST#u001', 'SK': 'PROFILE'},
    UpdateExpression='REMOVE deleted_at',
)

# เงื่อนไข (จองสต็อก)
try:
    table.update_item(
        Key={'PK': 'PROD#p001', 'SK': 'DETAIL'},
        UpdateExpression='SET stock = stock - :one',
        ConditionExpression='stock >= :one',
        ExpressionAttributeValues={':one': 1},
    )
except ClientError as e:
    if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
        print("สต็อกไม่พอ")
```

### Node.js
```javascript
import { UpdateCommand } from "@aws-sdk/lib-dynamodb";

await doc.send(new UpdateCommand({
  TableName: "shop",
  Key: { PK: "CUST#u001", SK: "PROFILE" },
  UpdateExpression: "SET #n = :name, updated_at = :ts",
  ExpressionAttributeNames: { "#n": "name" },
  ExpressionAttributeValues: { ":name": "Somchai J", ":ts": new Date().toISOString() },
}));

// atomic increment
await doc.send(new UpdateCommand({
  TableName: "shop",
  Key: { PK: "CUST#u001", SK: "STATS" },
  UpdateExpression: "ADD order_count :one",
  ExpressionAttributeValues: { ":one": 1 },
}));
```

## 2.4 Delete

### Python
```python
table.delete_item(Key={'PK': 'CUST#u001', 'SK': 'PROFILE'})

# ลบเมื่อมีอยู่จริง (ไม่ error ถ้าไม่มี)
table.delete_item(
    Key={'PK': 'CUST#u001', 'SK': 'PROFILE'},
    ConditionExpression='attribute_exists(PK)',
)
```

### Node.js
```javascript
import { DeleteCommand } from "@aws-sdk/lib-dynamodb";

await doc.send(new DeleteCommand({
  TableName: "shop",
  Key: { PK: "CUST#u001", SK: "PROFILE" },
}));
```

---

# ส่วนที่ 3: Query

## 3.1 Python — Query พื้นฐาน

```python
from boto3.dynamodb.conditions import Key, Attr

# ออเดอร์ทั้งหมดของ user
resp = table.query(
    KeyConditionExpression=Key('PK').eq('CUST#u001') & Key('SK').begins_with('ORDER#'),
)
for item in resp['Items']:
    print(item['SK'], item.get('total'))

# ตามช่วงวันที่ + เรียงใหม่→เก่า
resp = table.query(
    KeyConditionExpression=(
        Key('PK').eq('CUST#u001') &
        Key('SK').between('ORDER#2026-10-01', 'ORDER#2026-10-31')
    ),
    ScanIndexForward=False,
    Limit=20,
)

# + filter (⚠️ ไม่ลด RCU)
resp = table.query(
    KeyConditionExpression=Key('PK').eq('CUST#u001'),
    FilterExpression=Attr('status').eq('pending'),
)
```

## 3.2 Node.js — Query

```javascript
import { QueryCommand } from "@aws-sdk/lib-dynamodb";

const { Items } = await doc.send(new QueryCommand({
  TableName: "shop",
  KeyConditionExpression: "PK = :pk AND begins_with(SK, :prefix)",
  ExpressionAttributeValues: { ":pk": "CUST#u001", ":prefix": "ORDER#" },
}));

// ตามช่วงวันที่ + เรียงใหม่→เก่า
await doc.send(new QueryCommand({
  TableName: "shop",
  KeyConditionExpression: "PK = :pk AND SK BETWEEN :d1 AND :d2",
  ExpressionAttributeValues: {
    ":pk": "CUST#u001",
    ":d1": "ORDER#2026-10-01",
    ":d2": "ORDER#2026-10-31",
  },
  ScanIndexForward: false,
  Limit: 20,
}));
```

## 3.3 Query ผ่าน GSI

### Python
```python
resp = table.query(
    IndexName='status-index',
    KeyConditionExpression=Key('status').eq('pending'),
)
```

### Node.js
```javascript
await doc.send(new QueryCommand({
  TableName: "shop",
  IndexName: "status-index",
  KeyConditionExpression: "#s = :s",
  ExpressionAttributeNames: { "#s": "status" },
  ExpressionAttributeValues: { ":s": "pending" },
}));
```

---

# ส่วนที่ 4: ★ Pagination (สำคัญมาก)

## 4.1 Python — paginator (แนะนำ)

```python
# boto3 จัดการ pagination ให้อัตโนมัติ
paginator = client.get_paginator('query')
for page in paginator.paginate(
    TableName='shop',
    KeyConditionExpression='PK = :pk',
    ExpressionAttributeValues={':pk': {'S': 'CUST#u001'}},
):
    for item in page['Items']:
        print(item['SK'])
```

## 4.2 Python — manual (ควบคุมได้)

```python
items = []
kwargs = {
    'KeyConditionExpression': Key('PK').eq('CUST#u001'),
}
while True:
    resp = table.query(**kwargs)
    items.extend(resp['Items'])
    last_key = resp.get('LastEvaluatedKey')
    if not last_key:
        break
    kwargs['ExclusiveStartKey'] = last_key
```

## 4.3 Node.js — paginate

```javascript
import { paginateQuery } from "@aws-sdk/lib-dynamodb";

const paginator = paginateQuery({ client: doc }, {
  TableName: "shop",
  KeyConditionExpression: "PK = :pk",
  ExpressionAttributeValues: { ":pk": "CUST#u001" },
});

for await (const page of paginator) {
  for (const item of page.Items) console.log(item.SK);
}
```

**★ อย่าลืม pagination เสมอ:**
```
Query/Scan คืน ≤ 1 MB → ถ้ามีต่อต้อง loop
ถ้าไม่ loop → ★ ข้อมูลหายเงียบๆ (ได้แค่หน้าแรก)
```

---

# ส่วนที่ 5: Batch Operations

## 5.1 BatchWriteItem (≤ 25)

### Python
```python
with table.batch_writer() as batch:
    # boto3 จัดการ chunk + retry ให้
    for i in range(100):
        batch.put_item(Item={
            'PK': f'CUST#u{i:03d}',
            'SK': 'PROFILE',
            'name': f'User {i}',
        })
```

**manual (ต้องจัดการ UnprocessedItems เอง):**
```python
resp = client.batch_write_item(RequestItems={
    'shop': [
        {'PutRequest': {'Item': {'PK': {'S': 'CUST#u010'}, 'SK': {'S': 'PROFILE'}}}},
        {'DeleteRequest': {'Key': {'PK': {'S': 'CUST#u011'}, 'SK': {'S': 'PROFILE'}}}},
    ]
})
# ★ ต้อง retry UnprocessedItems!
unprocessed = resp.get('UnprocessedItems', {})
while unprocessed:
    resp = client.batch_write_item(RequestItems=unprocessed)
    unprocessed = resp.get('UnprocessedItems', {})
```

### Node.js
```javascript
import { BatchWriteCommand } from "@aws-sdk/lib-dynamodb";

await doc.send(new BatchWriteCommand({
  RequestItems: {
    shop: [
      { PutRequest: { Item: { PK: "CUST#u010", SK: "PROFILE" } } },
      { DeleteRequest: { Key: { PK: "CUST#u011", SK: "PROFILE" } } },
    ],
  },
}));
```

## 5.2 BatchGetItem (≤ 100)

### Python
```python
resp = client.batch_get_item(RequestItems={
    'shop': {
        'Keys': [
            {'PK': {'S': 'CUST#u001'}, 'SK': {'S': 'PROFILE'}},
            {'PK': {'S': 'CUST#u002'}, 'SK': {'S': 'PROFILE'}},
        ],
    }
})
for item in resp['Responses']['shop']:
    print(item)
```

---

# ส่วนที่ 6: Transaction

## 6.1 Python — TransactWriteItems

```python
client.transact_write_items(TransactItems=[
    {
        'Update': {
            'TableName': 'shop',
            'Key': {'PK': {'S': 'ACCOUNT#a1'}, 'SK': {'S': 'BALANCE'}},
            'UpdateExpression': 'SET balance = balance - :amt',
            'ConditionExpression': 'balance >= :amt',
            'ExpressionAttributeValues': {':amt': {'N': '1000'}},
        }
    },
    {
        'Update': {
            'TableName': 'shop',
            'Key': {'PK': {'S': 'ACCOUNT#a2'}, 'SK': {'S': 'BALANCE'}},
            'UpdateExpression': 'SET balance = balance + :amt',
            'ExpressionAttributeValues': {':amt': {'N': '1000'}},
        }
    },
    {
        'Put': {
            'TableName': 'shop',
            'Item': {
                'PK': {'S': 'TX#t001'},
                'SK': {'S': 'TRANSFER'},
                'amount': {'N': '1000'},
            },
            'ConditionExpression': 'attribute_not_exists(PK)',   # idempotency
        }
    },
])
```

### Node.js
```javascript
import { TransactWriteCommand } from "@aws-sdk/lib-dynamodb";

await doc.send(new TransactWriteCommand({
  TransactItems: [
    {
      Update: {
        TableName: "shop",
        Key: { PK: "ACCOUNT#a1", SK: "BALANCE" },
        UpdateExpression: "SET balance = balance - :amt",
        ConditionExpression: "balance >= :amt",
        ExpressionAttributeValues: { ":amt": 1000 },
      },
    },
    {
      Update: {
        TableName: "shop",
        Key: { PK: "ACCOUNT#a2", SK: "BALANCE" },
        UpdateExpression: "SET balance = balance + :amt",
        ExpressionAttributeValues: { ":amt": 1000 },
      },
    },
  ],
}));
```

**★ จำกัด:** ≤ 100 operations / transaction, ไม่เกิน 4 MB

---

# ส่วนที่ 7: Error Handling (สำคัญ)

## 7.1 Retry (Python)

```python
from botocore.config import Config

# retry อัตโนมัติ (boto3 built-in)
client = boto3.client('dynamodb', config=Config(
    retries={'max_attempts': 5, 'mode': 'adaptive'},
))
```

```
adaptive = ปรับตามอัตรา throttle (ดีสุด)
standard = backoff ปกติ
```

## 7.2 จัดการ error types

```python
import botocore.exceptions

try:
    table.put_item(Item={...}, ConditionExpression='attribute_not_exists(PK)')

except botocore.exceptions.ClientError as e:
    code = e.response['Error']['Code']

    if code == 'ConditionalCheckFailedException':
        # ★ ปกติ (ไม่ใช่ error ร้าย) — condition ไม่ผ่าน
        handle_conflict()

    elif code == 'ProvisionedThroughputExceededException':
        # retry (transient)
        retry_later()

    elif code == 'ValidationException':
        # ★ bug ในโค้ด — ต้องแก้
        raise

    elif code == 'ResourceNotFoundException':
        raise  # table ไม่มี
    else:
        raise
```

## 7.3 Idempotency pattern

```python
def create_order(order_id, user_id, amount):
    try:
        table.put_item(
            Item={
                'PK': f'ORDER#{order_id}',
                'SK': 'DETAIL',
                'user_id': user_id,
                'amount': amount,
            },
            # ★ ถ้ามีอยู่แล้ว → ล้มเงียบ (idempotent)
            ConditionExpression='attribute_not_exists(PK)',
        )
        return {'status': 'created'}
    except ClientError as e:
        if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
            # retry ด้วย order_id เดิม → คืนผลเดิมได้
            return {'status': 'already_exists'}
        raise
```

---

# ส่วนที่ 8: ตัวอย่างครบชุด — Repository Pattern

## 8.1 Python

```python
import boto3
from boto3.dynamodb.conditions import Key, Attr
from botocore.exceptions import ClientError

class ShopRepository:
    def __init__(self, table_name='shop', endpoint_url=None):
        kwargs = {'region_name': 'us-east-1'}
        if endpoint_url:
            kwargs.update(
                endpoint_url=endpoint_url,
                aws_access_key_id='dummy',
                aws_secret_access_key='dummy',
            )
        self.table = boto3.resource('dynamodb', **kwargs).Table(table_name)

    # ── user ──
    def get_user(self, user_id):
        resp = self.table.get_item(Key={'PK': f'CUST#{user_id}', 'SK': 'PROFILE'})
        return resp.get('Item')

    def put_user(self, user_id, name, email):
        try:
            self.table.put_item(
                Item={'PK': f'CUST#{user_id}', 'SK': 'PROFILE',
                      'name': name, 'email': email},
                ConditionExpression='attribute_not_exists(PK)',
            )
            return True
        except ClientError as e:
            if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
                return False
            raise

    # ── orders ──
    def create_order(self, user_id, order_date, order_id, total, status='pending'):
        self.table.put_item(Item={
            'PK': f'CUST#{user_id}',
            'SK': f'ORDER#{order_date}#{order_id}',
            'order_id': order_id,
            'total': total,
            'status': status,
        })

    def list_orders(self, user_id, limit=20):
        resp = self.table.query(
            KeyConditionExpression=(
                Key('PK').eq(f'CUST#{user_id}') &
                Key('SK').begins_with('ORDER#')
            ),
            ScanIndexForward=False,
            Limit=limit,
        )
        return resp['Items']

    def orders_by_status(self, status, limit=20):
        resp = self.table.query(
            IndexName='status-index',
            KeyConditionExpression=Key('status').eq(status),
            Limit=limit,
        )
        return resp['Items']

    # ── atomic ──
    def add_balance(self, user_id, amount):
        resp = self.table.update_item(
            Key={'PK': f'CUST#{user_id}', 'SK': 'PROFILE'},
            UpdateExpression='SET balance = if_not_exists(balance, :zero) + :amt',
            ExpressionAttributeValues={':amt': amount, ':zero': 0},
            ReturnValues='ALL_NEW',
        )
        return resp['Attributes']['balance']


# ── ใช้งาน ──
repo = ShopRepository(endpoint_url='http://localhost:8000')
repo.put_user('u001', 'Somchai', 'user@example.com')
repo.create_order('u001', '2026-10-05', 'o123', 1200, 'pending')
print(repo.list_orders('u001'))
print(repo.orders_by_status('pending'))
print(repo.add_balance('u001', 100))
```

## 8.2 Node.js

```javascript
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient, GetCommand, PutCommand, QueryCommand, UpdateCommand,
} from "@aws-sdk/lib-dynamodb";

export class ShopRepository {
  constructor({ tableName = "shop", endpoint } = {}) {
    const client = new DynamoDBClient(
      endpoint
        ? { endpoint, region: "us-east-1",
            credentials: { accessKeyId: "dummy", secretAccessKey: "dummy" } }
        : { region: "ap-southeast-1" }
    );
    this.doc = DynamoDBDocumentClient.from(client);
    this.table = tableName;
  }

  async getUser(userId) {
    const { Item } = await this.doc.send(new GetCommand({
      TableName: this.table,
      Key: { PK: `CUST#${userId}`, SK: "PROFILE" },
    }));
    return Item;
  }

  async putUser(userId, name, email) {
    try {
      await this.doc.send(new PutCommand({
        TableName: this.table,
        Item: { PK: `CUST#${userId}`, SK: "PROFILE", name, email },
        ConditionExpression: "attribute_not_exists(PK)",
      }));
      return true;
    } catch (e) {
      if (e.name === "ConditionalCheckFailedException") return false;
      throw e;
    }
  }

  async listOrders(userId, limit = 20) {
    const { Items } = await this.doc.send(new QueryCommand({
      TableName: this.table,
      KeyConditionExpression: "PK = :pk AND begins_with(SK, :prefix)",
      ExpressionAttributeValues: { ":pk": `CUST#${userId}`, ":prefix": "ORDER#" },
      ScanIndexForward: false,
      Limit: limit,
    }));
    return Items;
  }

  async ordersByStatus(status, limit = 20) {
    const { Items } = await this.doc.send(new QueryCommand({
      TableName: this.table,
      IndexName: "status-index",
      KeyConditionExpression: "#s = :s",
      ExpressionAttributeNames: { "#s": "status" },
      ExpressionAttributeValues: { ":s": status },
      Limit: limit,
    }));
    return Items;
  }

  async addBalance(userId, amount) {
    const { Attributes } = await this.doc.send(new UpdateCommand({
      TableName: this.table,
      Key: { PK: `CUST#${userId}`, SK: "PROFILE" },
      UpdateExpression: "SET balance = if_not_exists(balance, :zero) + :amt",
      ExpressionAttributeValues: { ":amt": amount, ":zero": 0 },
      ReturnValues: "ALL_NEW",
    }));
    return Attributes.balance;
  }
}
```

---

# ส่วนที่ 9: เทียบ Pattern กับ SQL

| SQL / ORM | DynamoDB |
|---|---|
| Connection pool | ⚠️ ไม่ต้อง (HTTP API) |
| `SELECT ... WHERE pk=` | `get_item` / `query` |
| `INSERT ... ON DUPLICATE` | `put_item` + `ConditionExpression` |
| `UPDATE SET x = x + 1` | `update_item` `SET x = x + :v` |
| `DELETE ... WHERE cond` | `delete_item` + ConditionExpression |
| `BEGIN...COMMIT` | `transact_write_items` |
| `LIMIT/OFFSET` | `Limit` + `ExclusiveStartKey` |
| Prepared statement | `ExpressionAttributeValues` (กัน injection) |
| Retry middleware | boto3 `Config(retries=...)` |
| N+1 query | ⚠️ BatchGet / denormalize |

---

# ส่วนที่ 10: ★ กับดักในโค้ด

```
① ลืม pagination → ข้อมูลหายเงียบๆ
   ✅ loop จน LastEvaluatedKey หายไป (หรือใช้ paginator)

② ใช้ put_item แทน update_item → ข้อมูล field อื่นหาย
   ✅ update_item สำหรับแก้บาง field

③ BatchWrite ไม่ retry UnprocessedItems → ข้อมูลหาย
   ✅ loop retry (หรือใช้ batch_writer ใน boto3)

④ hardcode credential
   ✅ IAM role / env var

⑤ ใช้ scan → แพง
   ✅ query + GSI

⑥ ไม่ handle ConditionalCheckFailedException
   → crash ทั้งที่ควรเป็น business logic ปกติ
   ✅ catch แยก (condition ≠ error)

⑦ float สำหรับเงิน
   ✅ integer (สตางค์) หรือ Decimal

⑧ ส่ง item > 400 KB → error
   ✅ แยก item / เก็บไฟล์ที่ S3

⑨ retry โดยไม่มี idempotency → เขียนซ้ำ
   ✅ condition + request-id
```

---

## ไฟล์ที่เกี่ยวข้อง

```
dynamodb-local-setup.md       ทดลอง (รันโค้ดกับ Local ได้)
dynamodb-query-reference.md   API ทั้งหมด
dynamodb-best-practices.md    แนวปฏิบัติ
migration-from-sql.md         ย้ายจาก SQL
```
