#!/usr/bin/env bash
# Seed thin samples + smoke DM image / card-attachment (server-local).
set -euo pipefail
API="${API:-http://127.0.0.1:3001/api}"
TS=$(date +%s)
A_PHONE="137$(printf '%08d' $((TS % 100000000)))"
B_PHONE="136$(printf '%08d' $(((TS + 9) % 100000000)))"
PASS='Test1234a'
BIRTH='1995-06-15'

jget() {
  python3 -c 'import json,sys
d=json.load(sys.stdin)
cur=d
for p in sys.argv[1].split("."):
  cur = cur.get(p) if isinstance(cur, dict) else None
print("" if cur is None else cur)' "$1"
}

register() {
  local phone="$1" code_resp code reg
  code_resp=$(curl -sS -X POST "$API/auth/send-code" -H 'Content-Type: application/json' \
    -d "{\"phone\":\"$phone\",\"captchaToken\":\"unconfigured-bypass\"}" || true)
  # When hCaptcha configured, inject verified token via temporary map is unavailable;
  # prefer AUTH_CAPTCHA_DIAG or use existing users. Fallback: try login of seed phones.
  code=$(printf '%s' "$code_resp" | jget data.code)
  if [[ -z "$code" ]]; then
    echo "send-code needs captcha; attempting prisma-backed seed helper" >&2
    return 1
  fi
  reg=$(curl -sS -X POST "$API/auth/register" -H 'Content-Type: application/json' \
    -d "{\"phone\":\"$phone\",\"code\":\"$code\",\"password\":\"$PASS\",\"birthday\":\"$BIRTH\"}")
  printf '%s' "$reg" | jget data.token
}

echo "seed phones A=$A_PHONE B=$B_PHONE"

# Load server .env when present (run from /opt/ninewood/server or with JWT_SECRET set)
if [[ -f .env ]]; then set -a; # shellcheck disable=SC1091
  source .env
  set +a
fi

# Prefer node seed when captcha blocks curl register
NODE_OUT=$(node --input-type=module <<'NODE' || true
import { PrismaClient } from '@prisma/client'
import bcrypt from 'bcryptjs'
import jwt from 'jsonwebtoken'
import fs from 'fs'

const prisma = new PrismaClient()
function loadSecret() {
  if (process.env.JWT_SECRET) return process.env.JWT_SECRET
  try {
    const m = fs.readFileSync('.env', 'utf8').match(/^JWT_SECRET=(.*)$/m)
    if (m) return m[1].trim()
  } catch {}
  return 'dev'
}
const secret = loadSecret()
const ts = Date.now()
const mkPhone = (n) => `137${String(ts + n).slice(-8)}`
async function ensureUser(phone, nick) {
  let u = await prisma.user.findFirst({ where: { phone } })
  if (!u) {
    const hash = await bcrypt.hash('Test1234a', 10)
    u = await prisma.user.create({
      data: {
        phone,
        passwordHash: hash,
        nickname: nick,
        birthday: new Date('1995-06-15'),
        certificationLevel: 'NONE',
        creditScore: 60,
        snatchCredits: 3,
      },
    })
    await prisma.walletHold.create({
      data: { userId: u.id, balance: 1000000, held: 0 },
    }).catch(async () => {
      // wallet may use different model; ignore
    })
  }
  const token = jwt.sign(
    { userId: u.id, phone: u.phone, certLevel: u.certificationLevel || 'NONE' },
    secret,
    { expiresIn: '7d' },
  )
  return { user: u, token }
}

const a = await ensureUser(mkPhone(1), `发卡方_${ts}`)
const b = await ensureUser(mkPhone(2), `收卡方_${ts}`)

let card = await prisma.serviceCard.findFirst({ where: { userId: a.user.id } })
if (!card) {
  card = await prisma.serviceCard.create({
    data: {
      id: `seed-sc-${ts}`,
      userId: a.user.id,
      title: `种子服务卡 ${ts}`,
      summary: '自动化播种',
      description: '用于验证聊天发卡与落库',
      category: '产品策略',
      serviceType: 'ONLINE',
      status: 'PUBLISHED',
      isPublic: true,
      publishedAt: new Date(),
      tags: ['种子'],
      paths: [],
    },
  })
}
await prisma.serviceCardClaim.upsert({
  where: { serviceCardId_label: { serviceCardId: card.id, label: '可用性验证' } },
  create: { serviceCardId: card.id, label: '可用性验证', description: '种子 claim', sortOrder: 0 },
  update: { description: '种子 claim' },
}).catch(() => {})

const expire = new Date(Date.now() + 30 * 60 * 1000)
let demand = await prisma.demand.create({
  data: {
    userId: a.user.id,
    title: `种子需求发卡 ${ts}`,
    description: '自动化验证 CardAttachment',
    expectedOutcome: '发出需求卡',
    minPrice: 100,
    category: '日常服务',
    serviceType: 'ONLINE',
    status: 'ACTIVE',
    isPublic: true,
    expireAt: expire,
    maxApplicants: 5,
    mediaUrls: ['/uploads/seed-placeholder.txt'],
  },
})

// Welfare sample: mark a demand as incentive if schema supports; else create via welfare route later
console.log(JSON.stringify({
  aToken: a.token,
  bToken: b.token,
  aUserId: a.user.id,
  bUserId: b.user.id,
  serviceCardId: card.id,
  demandId: demand.id,
}))
await prisma.$disconnect()
NODE
)

if [[ -z "$NODE_OUT" || "$NODE_OUT" != \{* ]]; then
  echo "node seed failed, trying captcha bypass register" >&2
  # last resort: if AUTH allows unconfigured
  A_TOKEN=$(register "$A_PHONE" || true)
  B_TOKEN=$(register "$B_PHONE" || true)
  [[ -n "$A_TOKEN" && -n "$B_TOKEN" ]] || { echo "cannot seed users" >&2; exit 1; }
  # minimal create via API omitted
  echo "registered via API but need cards manually" >&2
  exit 1
fi

A_TOKEN=$(printf '%s' "$NODE_OUT" | jget aToken)
B_TOKEN=$(printf '%s' "$NODE_OUT" | jget bToken)
SC_ID=$(printf '%s' "$NODE_OUT" | jget serviceCardId)
DEMAND_ID=$(printf '%s' "$NODE_OUT" | jget demandId)
B_UID=$(printf '%s' "$NODE_OUT" | jget bUserId)

echo "A_TOKEN ok SC=$SC_ID DEMAND=$DEMAND_ID -> B=$B_UID"

# Send service card
CARD=$(curl -sS -X POST "$API/messages/card-attachment" \
  -H "Authorization: Bearer $A_TOKEN" -H 'Content-Type: application/json' \
  -d "{\"toUserId\":\"$B_UID\",\"cardType\":\"SERVICE_CARD\",\"cardId\":\"$SC_ID\",\"content\":\"种子服务卡\"}")
echo "CARD_RESP=$CARD"
CARD_ATT=$(printf '%s' "$CARD" | jget data.cardAttachment.id)
[[ -n "$CARD_ATT" ]] || { echo "card send failed" >&2; exit 1; }

# Send demand card
DCARD=$(curl -sS -X POST "$API/messages/card-attachment" \
  -H "Authorization: Bearer $A_TOKEN" -H 'Content-Type: application/json' \
  -d "{\"toUserId\":\"$B_UID\",\"cardType\":\"DEMAND\",\"cardId\":\"$DEMAND_ID\",\"content\":\"种子需求卡\"}")
echo "DEMAND_CARD_RESP=$DCARD"
D_ATT=$(printf '%s' "$DCARD" | jget data.cardAttachment.id)
[[ -n "$D_ATT" ]] || { echo "demand card send failed" >&2; exit 1; }

# Send image
printf '\xff\xd8\xff\xd9' > /tmp/seed-tiny.jpg
IMG=$(curl -sS -X POST "$API/messages/send" \
  -H "Authorization: Bearer $A_TOKEN" \
  -F "toUserId=$B_UID" \
  -F "content=[图片]" \
  -F "file=@/tmp/seed-tiny.jpg;type=image/jpeg")
echo "IMG_RESP=$IMG"
IMG_TYPE=$(printf '%s' "$IMG" | jget data.type)
[[ "$IMG_TYPE" == "IMAGE" || -n "$(printf '%s' "$IMG" | jget data.id)" ]] || { echo "image send failed" >&2; exit 1; }

# Welfare publish (required: title, description, expectedOutcome, minPrice)
WEL=$(curl -sS -X POST "$API/welfare/demands" \
  -H "Authorization: Bearer $A_TOKEN" -H 'Content-Type: application/json' \
  -d "{\"title\":\"种子福利$TS\",\"description\":\"可认领激励任务烟测\",\"expectedOutcome\":\"完成现场协助\",\"minPrice\":50}" || true)
echo "WELFARE_RESP=$(printf '%s' "$WEL" | head -c 240)"

COUNT=$(node -e 'const {PrismaClient}=require("@prisma/client");(async()=>{const p=new PrismaClient();console.log(await p.cardAttachment.count());await p.$disconnect()})()' 2>/dev/null \
  || docker exec ninewood-postgres-1 psql -U ninewood -d ninewood -tAc 'SELECT count(*) FROM "CardAttachment"' 2>/dev/null \
  || echo '?')
echo "CardAttachment_count=$COUNT"
echo "SMOKE_OK cardAtt=$CARD_ATT demandAtt=$D_ATT"
