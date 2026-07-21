#!/usr/bin/env bash
# AC-P1 E4：服务费托管语义
# A 成功路径：prepay=HOLD → confirm=CONSUMED + platformRevenue
# C 取消路径：prepay=HOLD → cancel=RELEASED + 余额回滚
# B 争议退款：prepay=HOLD → dispute → admin refund=RELEASED
set -euo pipefail

API="${API:-http://127.0.0.1:3001/api}"
TS=$(date +%s)
BATCH="acp1-$TS"
REQ_PHONE="139$(printf '%08d' $((TS % 100000000)))"
PRO_PHONE="138$(printf '%08d' $(((TS + 17) % 100000000)))"
PASS='Test1234a'
BIRTH='1995-06-15'
EVIDENCE="/tmp/ninewood-acp1-e4-$TS.md"
FAILS=0

# 仅在服务器本机跑：从 .env 读 ADMIN_API_KEY，不打印密钥
if [[ -z "${ADMIN_API_KEY:-}" && -f /opt/ninewood/server/.env ]]; then
  # shellcheck disable=SC1091
  set -a
  # shellcheck disable=SC1091
  source /opt/ninewood/server/.env
  set +a
fi
ADMIN_API_KEY="${ADMIN_API_KEY:-}"

jget() {
  local path="$1"
  python3 -c 'import json,sys
d=json.load(sys.stdin)
cur=d
for p in sys.argv[1].split("."):
  cur = cur.get(p) if isinstance(cur, dict) else None
print("" if cur is None else cur)' "$path"
}

need() {
  local label="$1" value="$2"
  if [[ -z "$value" || "$value" == "None" ]]; then
    echo "FAIL: $label missing" >&2
    FAILS=$((FAILS + 1))
    return 1
  fi
  return 0
}

assert_eq() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" != "$want" ]]; then
    echo "FAIL: $label got='$got' want='$want'" >&2
    FAILS=$((FAILS + 1))
    return 1
  fi
  echo "PASS: $label = $want"
  return 0
}

assert_num_eq() {
  local label="$1" got="$2" want="$3"
  python3 - "$label" "$got" "$want" <<'PY' || { FAILS=$((FAILS + 1)); return 1; }
import sys
label, got, want = sys.argv[1], sys.argv[2], sys.argv[3]
try:
  g = float(got); w = float(want)
except Exception:
  print(f"FAIL: {label} non-numeric got={got!r} want={want!r}", file=sys.stderr)
  sys.exit(1)
if abs(g - w) > 0.01:
  print(f"FAIL: {label} got={g} want={w}", file=sys.stderr)
  sys.exit(1)
print(f"PASS: {label} = {w}")
PY
}

balance() {
  local token="$1"
  local w
  w=$(curl -sS "$API/wallet/balance" -H "Authorization: Bearer $token")
  local bal
  bal=$(printf '%s' "$w" | jget data.balance)
  if [[ -z "$bal" ]]; then bal=$(printf '%s' "$w" | jget balance); fi
  printf '%s' "${bal:-0}"
}

hold_status() {
  local order_id="$1"
  docker exec ninewood-postgres-1 psql -U ninewood -d ninewood -Atc \
    "SELECT status FROM \"WalletServiceFeeHold\" WHERE \"orderId\"='$order_id' LIMIT 1;"
}

hold_amount() {
  local order_id="$1"
  docker exec ninewood-postgres-1 psql -U ninewood -d ninewood -Atc \
    "SELECT amount FROM \"WalletServiceFeeHold\" WHERE \"orderId\"='$order_id' LIMIT 1;"
}

settlement_revenue() {
  local demand_id="$1"
  docker exec ninewood-postgres-1 psql -U ninewood -d ninewood -Atc \
    "SELECT \"platformRevenue\" FROM \"Settlement\" WHERE \"demandId\"='$demand_id' LIMIT 1;"
}

seed_user() {
  local phone="$1"
  local nickname="acp1_${phone: -4}"
  PHONE="$phone" PASS="$PASS" NICK="$nickname" node --import tsx <<'NODE'
import bcrypt from 'bcryptjs'
import { prisma } from './src/lib/prisma.ts'
import { config } from './src/config.ts'

const phone = process.env.PHONE
const password = process.env.PASS
const nickname = process.env.NICK
if (!phone || !password || !nickname) {
  console.error('missing env')
  process.exit(1)
}
const hash = await bcrypt.hash(password, 12)
const birthday = new Date('1995-06-15')
const existing = await prisma.user.findUnique({ where: { phone } })
if (!existing) {
  await prisma.user.create({
    data: {
      phone,
      passwordHash: hash,
      nickname,
      birthday,
      points: config.defaultUserPoints ?? 1_000_000,
      certificationLevel: 'NONE',
      creditScore: 60,
    },
  })
  console.error(`seeded ${phone}`)
} else {
  console.error(`exists ${phone}`)
}
await prisma.$disconnect()
NODE
}

login_token() {
  local phone="$1"
  local resp token
  resp=$(curl -sS -X POST "$API/auth/login" -H 'Content-Type: application/json' \
    -d "{\"phone\":\"$phone\",\"password\":\"$PASS\"}")
  token=$(printf '%s' "$resp" | jget data.token)
  if [[ -z "$token" ]]; then
    echo "login failed for $phone: $resp" >&2
    exit 1
  fi
  printf '%s' "$token"
}

register() {
  local phone="$1"
  seed_user "$phone"
  login_token "$phone"
}

make_order() {
  local req_token="$1" pro_token="$2" title="$3" min_price="$4" suffix="$5"
  local expire create demand_id apply app_id accept order_id
  expire=$(python3 -c 'from datetime import datetime,timedelta,timezone; print((datetime.now(timezone.utc)+timedelta(minutes=30)).strftime("%Y-%m-%dT%H:%M:%S.000Z"))')
  create=$(curl -sS -X POST "$API/demands" \
    -H "Authorization: Bearer $req_token" \
    -H "Idempotency-Key: $BATCH-create-$suffix" \
    -F "title=$title" \
    -F "description=AC-P1 E4 自动化" \
    -F "expectedOutcome=验证服务费托管语义" \
    -F "minPrice=$min_price" \
    -F "category=日常服务" \
    -F "serviceType=ONLINE" \
    -F "expireAt=$expire" \
    -F "maxApplicants=5" \
    -F "visibilityWindow=30")
  demand_id=$(printf '%s' "$create" | jget data.id)
  if [[ -z "$demand_id" ]]; then
    echo "FAIL: create demand $suffix: $create" >&2
    FAILS=$((FAILS + 1))
    return 1
  fi
  apply=$(curl -sS -X POST "$API/demands/$demand_id/request" \
    -H "Authorization: Bearer $pro_token" \
    -H "Content-Type: application/json" \
    -H "Idempotency-Key: $BATCH-req-$suffix" \
    -d '{"message":"ac-p1 provider"}')
  app_id=$(printf '%s' "$apply" | jget data.id)
  if [[ -z "$app_id" ]]; then
    echo "FAIL: request $suffix: $apply" >&2
    FAILS=$((FAILS + 1))
    return 1
  fi
  accept=$(curl -sS -X POST "$API/demands/$demand_id/accept/$app_id" \
    -H "Authorization: Bearer $req_token" \
    -H "Idempotency-Key: $BATCH-acc-$suffix")
  order_id=$(printf '%s' "$accept" | jget data.orderId)
  if [[ -z "$order_id" ]]; then
    echo "FAIL: accept $suffix: $accept" >&2
    FAILS=$((FAILS + 1))
    return 1
  fi
  printf '%s %s' "$demand_id" "$order_id"
}

echo "AC-P1 E4 batch=$BATCH requester=$REQ_PHONE provider=$PRO_PHONE"
{
  echo "## AC-P1 E4 batch $BATCH ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
  echo
  echo "requester=$REQ_PHONE provider=$PRO_PHONE"
  echo
} > "$EVIDENCE"

REQ_TOKEN=$(register "$REQ_PHONE")
PRO_TOKEN=$(register "$PRO_PHONE")
BAL0=$(balance "$REQ_TOKEN")
echo "A0 requester balance=$BAL0" | tee -a "$EVIDENCE"

extract_fee() {
  local json="$1"
  local fee
  fee=$(printf '%s' "$json" | jget data.serviceFee)
  if [[ -z "$fee" ]]; then fee=$(printf '%s' "$json" | jget data.payableNow); fi
  # FlexibleDecimal 形态
  if [[ -z "$fee" ]]; then fee=$(printf '%s' "$json" | jget data.serviceFee.value); fi
  printf '%s' "$fee"
}

# ---------- Path A: success ----------
echo | tee -a "$EVIDENCE"
echo "### Path A success (HOLD → CONSUMED)" | tee -a "$EVIDENCE"
ORDER_PAIR=$(make_order "$REQ_TOKEN" "$PRO_TOKEN" "ACP1成功$TS" 100 a) || exit 1
DEMAND_A=${ORDER_PAIR%% *}
ORDER_A=${ORDER_PAIR##* }
BAL_A1=$(balance "$REQ_TOKEN")
echo "A1 after publish demand=$DEMAND_A order=$ORDER_A bal=$BAL_A1" | tee -a "$EVIDENCE"

BD=$(curl -sS "$API/orders/$ORDER_A/pay-breakdown" -H "Authorization: Bearer $REQ_TOKEN")
FEE_A=$(extract_fee "$BD")
if [[ -z "$FEE_A" ]]; then
  echo "WARN: pay-breakdown missing fee, fallback 5%: $BD" | tee -a "$EVIDENCE"
  FEE_A=5
fi
need "fee A" "$FEE_A"
echo "A4 fee=$FEE_A breakdown=$(printf '%s' "$BD" | head -c 200)" | tee -a "$EVIDENCE"

PREPAY_A=$(curl -sS -X POST "$API/orders/$ORDER_A/prepay" \
  -H "Authorization: Bearer $REQ_TOKEN" \
  -H "Idempotency-Key: $BATCH-prepay-a")
echo "A5 prepay=$(printf '%s' "$PREPAY_A" | jget data.message)$(printf '%s' "$PREPAY_A" | jget message)" | tee -a "$EVIDENCE"
BAL_A5=$(balance "$REQ_TOKEN")
STATUS_A5=$(hold_status "$ORDER_A")
AMT_A5=$(hold_amount "$ORDER_A")
assert_eq "A5 hold status" "$STATUS_A5" "HELD"
assert_num_eq "A5 hold amount" "$AMT_A5" "$FEE_A"
assert_num_eq "A5 balance drop by fee" "$(python3 -c "print($BAL_A1 - $BAL_A5)")" "$FEE_A"

curl -sS -X POST "$API/orders/$ORDER_A/complete" -H "Authorization: Bearer $PRO_TOKEN" \
  -H "Idempotency-Key: $BATCH-complete-a" >/dev/null
CONFIRM_A=$(curl -sS -X POST "$API/orders/$ORDER_A/confirm" \
  -H "Authorization: Bearer $REQ_TOKEN" \
  -H "Idempotency-Key: $BATCH-confirm-a")
echo "A7 confirm=$(printf '%s' "$CONFIRM_A" | jget data.message)$(printf '%s' "$CONFIRM_A" | jget message)" | tee -a "$EVIDENCE"
STATUS_A7=$(hold_status "$ORDER_A")
REV_A=$(settlement_revenue "$DEMAND_A")
assert_eq "A7 hold status" "$STATUS_A7" "CONSUMED"
assert_num_eq "A7 platformRevenue" "$REV_A" "$FEE_A"
BAL_A7=$(balance "$REQ_TOKEN")
BAL_PRO=$(balance "$PRO_TOKEN")
echo "A7 requester bal=$BAL_A7 provider bal=$BAL_PRO revenue=$REV_A" | tee -a "$EVIDENCE"

# ---------- Path C: cancel after prepay ----------
echo | tee -a "$EVIDENCE"
echo "### Path C cancel after prepay (HOLD → RELEASED)" | tee -a "$EVIDENCE"
ORDER_PAIR=$(make_order "$REQ_TOKEN" "$PRO_TOKEN" "ACP1取消$TS" 80 c) || exit 1
DEMAND_C=${ORDER_PAIR%% *}
ORDER_C=${ORDER_PAIR##* }
BAL_C1=$(balance "$REQ_TOKEN")
BD_C=$(curl -sS "$API/orders/$ORDER_C/pay-breakdown" -H "Authorization: Bearer $REQ_TOKEN")
FEE_C=$(extract_fee "$BD_C")
if [[ -z "$FEE_C" ]]; then FEE_C=4; fi
curl -sS -X POST "$API/orders/$ORDER_C/prepay" \
  -H "Authorization: Bearer $REQ_TOKEN" \
  -H "Idempotency-Key: $BATCH-prepay-c" >/dev/null
BAL_C5=$(balance "$REQ_TOKEN")
STATUS_C5=$(hold_status "$ORDER_C")
assert_eq "C5 hold status" "$STATUS_C5" "HELD"
assert_num_eq "C5 balance drop by fee" "$(python3 -c "print($BAL_C1 - $BAL_C5)")" "$FEE_C"

CANCEL=$(curl -sS -X POST "$API/orders/$ORDER_C/cancel" \
  -H "Authorization: Bearer $REQ_TOKEN" \
  -H "Idempotency-Key: $BATCH-cancel-c")
echo "C1 cancel=$(printf '%s' "$CANCEL" | jget data.message)$(printf '%s' "$CANCEL" | jget message)" | tee -a "$EVIDENCE"
STATUS_C1=$(hold_status "$ORDER_C")
BAL_C1_AFTER=$(balance "$REQ_TOKEN")
assert_eq "C1 hold status" "$STATUS_C1" "RELEASED"
assert_num_eq "C1 balance restored" "$BAL_C1_AFTER" "$BAL_C1"

# ---------- Path B: dispute refund ----------
echo | tee -a "$EVIDENCE"
echo "### Path B dispute refund (HOLD → RELEASED via admin)" | tee -a "$EVIDENCE"
if [[ -z "$ADMIN_API_KEY" ]]; then
  echo "FAIL: ADMIN_API_KEY missing; skip dispute resolve" >&2
  FAILS=$((FAILS + 1))
else
  ORDER_PAIR=$(make_order "$REQ_TOKEN" "$PRO_TOKEN" "ACP1争议$TS" 60 b) || exit 1
  DEMAND_B=${ORDER_PAIR%% *}
  ORDER_B=${ORDER_PAIR##* }
  BAL_B1=$(balance "$REQ_TOKEN")
  BD_B=$(curl -sS "$API/orders/$ORDER_B/pay-breakdown" -H "Authorization: Bearer $REQ_TOKEN")
  FEE_B=$(extract_fee "$BD_B")
  if [[ -z "$FEE_B" ]]; then FEE_B=3; fi
  curl -sS -X POST "$API/orders/$ORDER_B/prepay" \
    -H "Authorization: Bearer $REQ_TOKEN" \
    -H "Idempotency-Key: $BATCH-prepay-b" >/dev/null
  assert_eq "B5 hold status" "$(hold_status "$ORDER_B")" "HELD"
  curl -sS -X POST "$API/orders/$ORDER_B/complete" -H "Authorization: Bearer $PRO_TOKEN" \
    -H "Idempotency-Key: $BATCH-complete-b" >/dev/null

  # dispute 需要至少一份证据 URL
  DISPUTE=$(curl -sS -X POST "$API/orders/$ORDER_B/dispute" \
    -H "Authorization: Bearer $REQ_TOKEN" \
    -H "Content-Type: application/json" \
    -H "Idempotency-Key: $BATCH-dispute-b" \
    -d '{"reason":"AC-P1 dispute smoke","description":"AC-P1 dispute smoke","evidenceUrls":["/uploads/e4-acp1-evidence.txt"]}')
  echo "B7 dispute=$(printf '%s' "$DISPUTE" | jget data.message)$(printf '%s' "$DISPUTE" | jget message)$(printf '%s' "$DISPUTE" | jget data.status)" | tee -a "$EVIDENCE"
  DSTATUS=$(printf '%s' "$DISPUTE" | jget data.status)
  assert_eq "B7 order status" "$DSTATUS" "DISPUTED"

  RESOLVE=$(curl -sS -X POST "$API/admin/disputes/$ORDER_B/resolve" \
    -H "X-Admin-Api-Key: $ADMIN_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"action":"refund"}')
  echo "B8 resolve=$(printf '%s' "$RESOLVE" | jget data.message)$(printf '%s' "$RESOLVE" | jget message)" | tee -a "$EVIDENCE"
  STATUS_B8=$(hold_status "$ORDER_B")
  BAL_B8=$(balance "$REQ_TOKEN")
  assert_eq "B8 hold status" "$STATUS_B8" "RELEASED"
  # 预付后余额 + 至少退回服务费（发布托管也可能一并释放，故用下限断言）
  python3 - "$BAL_B8" "$BAL_B1" "$FEE_B" <<'PY' || { echo "FAIL: B8 fee not fully refunded" >&2; FAILS=$((FAILS + 1)); }
import sys
bal8, bal1, fee = map(float, sys.argv[1:4])
# bal1=预付前；预付扣 fee；退款后至少回到 bal1（服务费全额退），通常还会退发布托管
if bal8 + 0.02 < bal1:
  print(f"FAIL: B8 balance {bal8} < prepay-before {bal1}", file=sys.stderr)
  sys.exit(1)
print(f"PASS: B8 balance restored to >= prepay-before ({bal8} >= {bal1})")
PY
fi

echo | tee -a "$EVIDENCE"
echo "FAILS=$FAILS" | tee -a "$EVIDENCE"
echo "EVIDENCE=$EVIDENCE"
echo "ORDER_A=$ORDER_A ORDER_C=$ORDER_C ORDER_B=${ORDER_B:-}"

if [[ "$FAILS" -gt 0 ]]; then
  echo "AC-P1 E4 FAILED ($FAILS)" >&2
  exit 1
fi
echo "AC-P1 E4 PASSED"
exit 0
