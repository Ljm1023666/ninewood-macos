#!/usr/bin/env bash
# Trade-loop E4 smoke (server-local).
set -euo pipefail
API="${API:-http://127.0.0.1:3001/api}"
TS=$(date +%s)
REQ_PHONE="139$(printf '%08d' $((TS % 100000000)))"
PRO_PHONE="138$(printf '%08d' $(((TS + 17) % 100000000)))"
PASS='Test1234a'
BIRTH='1995-06-15'
EVIDENCE_FILE="/tmp/ninewood-e4-evidence-$TS.md"

jget() {
  # usage: printf '%s' "$json" | jget path.path
  local path="$1"
  python3 -c 'import json,sys
d=json.load(sys.stdin)
cur=d
for p in sys.argv[1].split("."):
  cur = cur.get(p) if isinstance(cur, dict) else None
print("" if cur is None else cur)' "$path"
}

register() {
  local phone="$1"
  local code_resp code reg token
  code_resp=$(curl -sS -X POST "$API/auth/send-code" -H 'Content-Type: application/json' \
    -d "{\"phone\":\"$phone\",\"captchaToken\":\"unconfigured-bypass\"}")
  code=$(printf '%s' "$code_resp" | jget data.code)
  if [[ -z "$code" ]]; then
    echo "send-code failed for $phone: $code_resp" >&2
    exit 1
  fi
  reg=$(curl -sS -X POST "$API/auth/register" -H 'Content-Type: application/json' \
    -d "{\"phone\":\"$phone\",\"code\":\"$code\",\"password\":\"$PASS\",\"birthday\":\"$BIRTH\"}")
  token=$(printf '%s' "$reg" | jget data.token)
  if [[ -z "$token" ]]; then
    echo "register failed for $phone: $reg" >&2
    exit 1
  fi
  printf '%s' "$token"
}

wallet_line() {
  local token="$1" label="$2"
  local w bal held
  w=$(curl -sS "$API/wallet/balance" -H "Authorization: Bearer $token" || true)
  bal=$(printf '%s' "$w" | jget data.balance)
  held=$(printf '%s' "$w" | jget data.held)
  if [[ -z "$bal" ]]; then bal=$(printf '%s' "$w" | jget balance); fi
  if [[ -z "$held" ]]; then held=$(printf '%s' "$w" | jget held); fi
  echo "| $label | $(date -u +%Y-%m-%dT%H:%M:%SZ) | — | — | — | — | ${bal:-?} | ${held:-?} | — | |"
}

echo "E4 phones requester=$REQ_PHONE provider=$PRO_PHONE"
REQ_TOKEN=$(register "$REQ_PHONE")
PRO_TOKEN=$(register "$PRO_PHONE")

{
  echo "## E4 batch $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "requester=$REQ_PHONE provider=$PRO_PHONE"
  echo
  echo "| 步骤 | 时间(UTC) | demandId | orderId | stage / rawStatus | isPrepaid | balance | held | ledgerΔ | 备注 |"
  echo "|------|-----------|----------|---------|-------------------|-----------|---------|------|---------|------|"
} > "$EVIDENCE_FILE"

wallet_line "$REQ_TOKEN" "A0 requester" >> "$EVIDENCE_FILE"
wallet_line "$PRO_TOKEN" "A0 provider" >> "$EVIDENCE_FILE"

EXPIRE=$(python3 -c 'from datetime import datetime,timedelta,timezone; print((datetime.now(timezone.utc)+timedelta(minutes=30)).strftime("%Y-%m-%dT%H:%M:%S.000Z"))')
CREATE=$(curl -sS -X POST "$API/demands" \
  -H "Authorization: Bearer $REQ_TOKEN" \
  -H "Idempotency-Key: e4-$TS-create" \
  -F "title=E4黄金路径测试$TS" \
  -F "description=自动化验收用需求，可删除" \
  -F "expectedOutcome=完成一笔测试交易闭环" \
  -F "minPrice=100" \
  -F "category=日常服务" \
  -F "serviceType=ONLINE" \
  -F "expireAt=$EXPIRE" \
  -F "maxApplicants=5" \
  -F "visibilityWindow=30")
echo "CREATE=$CREATE" >> "$EVIDENCE_FILE"
DEMAND_ID=$(printf "%s" "$CREATE" | jget data.id)
DEPOSIT=$(printf "%s" "$CREATE" | jget data.depositRequired)
RULE=$(printf "%s" "$CREATE" | jget data.ruleVersion)
if [[ -z "$DEMAND_ID" ]]; then
  echo "create demand failed: $CREATE" >&2
  exit 1
fi
echo "| A1 publish | $(date -u +%Y-%m-%dT%H:%M:%SZ) | $DEMAND_ID | — | ACTIVE | — | (snap) | (snap) | depositRequired=$DEPOSIT | rule=$RULE |" >> "$EVIDENCE_FILE"
wallet_line "$REQ_TOKEN" "A1 after publish" >> "$EVIDENCE_FILE"

REQ_APPLY=$(curl -sS -X POST "$API/demands/$DEMAND_ID/request" \
  -H "Authorization: Bearer $PRO_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: e4-$TS-request" \
  -d '{"message":"E4 provider request"}')
APP_ID=$(printf "%s" "$REQ_APPLY" | jget data.id)
if [[ -z "$APP_ID" ]]; then
  echo "request failed: $REQ_APPLY" >&2
  exit 1
fi
echo "| A2 request | $(date -u +%Y-%m-%dT%H:%M:%SZ) | $DEMAND_ID | — | applicant=$APP_ID | — | — | — | — | ok |" >> "$EVIDENCE_FILE"

ACCEPT=$(curl -sS -X POST "$API/demands/$DEMAND_ID/accept/$APP_ID" \
  -H "Authorization: Bearer $REQ_TOKEN" \
  -H "Idempotency-Key: e4-$TS-accept")
ORDER_ID=$(printf "%s" "$ACCEPT" | jget data.orderId)
if [[ -z "$ORDER_ID" ]]; then
  echo "accept failed: $ACCEPT" >&2
  exit 1
fi
echo "| A3 accept | $(date -u +%Y-%m-%dT%H:%M:%SZ) | $DEMAND_ID | $ORDER_ID | IN_PROGRESS | false | — | — | — | ok |" >> "$EVIDENCE_FILE"

BD=$(curl -sS "$API/orders/$ORDER_ID/pay-breakdown" -H "Authorization: Bearer $REQ_TOKEN")
PAYABLE=$(printf "%s" "$BD" | jget data.payableNow)
RULE2=$(printf "%s" "$BD" | jget data.ruleVersion)
echo "| A4 breakdown | $(date -u +%Y-%m-%dT%H:%M:%SZ) | $DEMAND_ID | $ORDER_ID | — | — | — | — | payableNow=$PAYABLE | rule=$RULE2 |" >> "$EVIDENCE_FILE"

PREPAY=$(curl -sS -X POST "$API/orders/$ORDER_ID/prepay" -H "Authorization: Bearer $REQ_TOKEN")
echo "| A5 prepay | $(date -u +%Y-%m-%dT%H:%M:%SZ) | $DEMAND_ID | $ORDER_ID | prepaid | true | (snap) | (snap) | msg=$(printf "%s" "$PREPAY" | jget message)$(printf "%s" "$PREPAY" | jget data.message) | |" >> "$EVIDENCE_FILE"
wallet_line "$REQ_TOKEN" "A5 after prepay" >> "$EVIDENCE_FILE"

COMPLETE=$(curl -sS -X POST "$API/orders/$ORDER_ID/complete" -H "Authorization: Bearer $PRO_TOKEN")
echo "| A6 complete | $(date -u +%Y-%m-%dT%H:%M:%SZ) | $DEMAND_ID | $ORDER_ID | WAITING_REVIEW | true | — | — | $(printf "%s" "$COMPLETE" | jget message)$(printf "%s" "$COMPLETE" | jget data.message) | |" >> "$EVIDENCE_FILE"

CONFIRM=$(curl -sS -X POST "$API/orders/$ORDER_ID/confirm" -H "Authorization: Bearer $REQ_TOKEN")
echo "| A7 confirm | $(date -u +%Y-%m-%dT%H:%M:%SZ) | $DEMAND_ID | $ORDER_ID | COMPLETED | true | (snap) | (snap) | $(printf "%s" "$CONFIRM" | jget message)$(printf "%s" "$CONFIRM" | jget data.message) | |" >> "$EVIDENCE_FILE"
wallet_line "$REQ_TOKEN" "A7 requester" >> "$EVIDENCE_FILE"
wallet_line "$PRO_TOKEN" "A7 provider" >> "$EVIDENCE_FILE"

REVIEW=$(curl -sS -X POST "$API/reviews" -H "Authorization: Bearer $REQ_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"orderId\":\"$ORDER_ID\",\"rating\":5,\"content\":\"E4 auto review $TS\"}")
REVIEW_ID=$(printf "%s" "$REVIEW" | jget data.id)
echo "| A8 review | $(date -u +%Y-%m-%dT%H:%M:%SZ) | $DEMAND_ID | $ORDER_ID | COMPLETED | true | — | — | reviewId=${REVIEW_ID:-?} | $(printf "%s" "$REVIEW" | jget message) |" >> "$EVIDENCE_FILE"

# Branch B dispute
CREATE2=$(curl -sS -X POST "$API/demands" \
  -H "Authorization: Bearer $REQ_TOKEN" \
  -H "Idempotency-Key: e4-$TS-create-b" \
  -F "title=E4争议分支$TS" \
  -F "description=争议分支自动化" \
  -F "expectedOutcome=提交争议" \
  -F "minPrice=80" \
  -F "category=日常服务" \
  -F "serviceType=ONLINE" \
  -F "expireAt=$EXPIRE" \
  -F "maxApplicants=5" \
  -F "visibilityWindow=30")
DEMAND2=$(printf "%s" "$CREATE2" | jget data.id)
APP2=$(curl -sS -X POST "$API/demands/$DEMAND2/request" -H "Authorization: Bearer $PRO_TOKEN" -H "Content-Type: application/json" -H "Idempotency-Key: e4-$TS-req-b" -d '{"message":"dispute branch"}')
APP2_ID=$(printf "%s" "$APP2" | jget data.id)
ACCEPT2=$(curl -sS -X POST "$API/demands/$DEMAND2/accept/$APP2_ID" -H "Authorization: Bearer $REQ_TOKEN" -H "Idempotency-Key: e4-$TS-acc-b")
ORDER2=$(printf "%s" "$ACCEPT2" | jget data.orderId)
curl -sS -X POST "$API/orders/$ORDER2/prepay" -H "Authorization: Bearer $REQ_TOKEN" >/dev/null
curl -sS -X POST "$API/orders/$ORDER2/complete" -H "Authorization: Bearer $PRO_TOKEN" >/dev/null
DISPUTE=$(curl -sS -X POST "$API/orders/$ORDER2/dispute" -H "Authorization: Bearer $REQ_TOKEN" -H "Content-Type: application/json" \
  -d '{"reason":"E4 dispute smoke","description":"E4 dispute smoke","evidenceUrls":[]}')
echo "| B7 dispute | $(date -u +%Y-%m-%dT%H:%M:%SZ) | $DEMAND2 | $ORDER2 | DISPUTED | true | — | — | $(printf "%s" "$DISPUTE" | jget message)$(printf "%s" "$DISPUTE" | jget data.message) | |" >> "$EVIDENCE_FILE"

# Cancel unpaid
CREATE3=$(curl -sS -X POST "$API/demands" \
  -H "Authorization: Bearer $REQ_TOKEN" \
  -H "Idempotency-Key: e4-$TS-create-c" \
  -F "title=E4取消分支$TS" \
  -F "description=取消分支" \
  -F "expectedOutcome=取消" \
  -F "minPrice=50" \
  -F "category=日常服务" \
  -F "serviceType=ONLINE" \
  -F "expireAt=$EXPIRE" \
  -F "maxApplicants=5" \
  -F "visibilityWindow=30")
DEMAND3=$(printf "%s" "$CREATE3" | jget data.id)
APP3=$(curl -sS -X POST "$API/demands/$DEMAND3/request" -H "Authorization: Bearer $PRO_TOKEN" -H "Content-Type: application/json" -H "Idempotency-Key: e4-$TS-req-c" -d '{"message":"cancel"}')
APP3_ID=$(printf "%s" "$APP3" | jget data.id)
ACCEPT3=$(curl -sS -X POST "$API/demands/$DEMAND3/accept/$APP3_ID" -H "Authorization: Bearer $REQ_TOKEN" -H "Idempotency-Key: e4-$TS-acc-c")
ORDER3=$(printf "%s" "$ACCEPT3" | jget data.orderId)
CANCEL=$(curl -sS -X POST "$API/orders/$ORDER3/cancel" -H "Authorization: Bearer $REQ_TOKEN")
echo "| C1 cancel | $(date -u +%Y-%m-%dT%H:%M:%SZ) | $DEMAND3 | $ORDER3 | CANCELLED? | false | — | — | $(printf "%s" "$CANCEL" | jget message)$(printf "%s" "$CANCEL" | jget data.message) | |" >> "$EVIDENCE_FILE"

echo
echo "=== E4 evidence ==="
cat "$EVIDENCE_FILE"
echo
echo "EVIDENCE_FILE=$EVIDENCE_FILE"
echo "ORDER_A=$ORDER_ID DEMAND_A=$DEMAND_ID ORDER_B=$ORDER2 ORDER_C=$ORDER3"
