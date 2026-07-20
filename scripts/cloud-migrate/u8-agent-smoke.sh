#!/usr/bin/env bash
# U8 Agent smoke: auth → conversation CRUD → SSE stream → (optional) write-tool pending
set -euo pipefail
API="${API:-http://127.0.0.1:3001/api}"
TS=$(date +%s)
# 生产已开 hCaptcha 时无法走注册 bypass；默认用设计预览种子号登录
PHONE="${AGENT_SMOKE_PHONE:-13906060601}"
PASS="${AGENT_SMOKE_PASS:-Test1234a}"
OUT="/tmp/ninewood-u8-agent-$TS.md"
STREAM_TIMEOUT="${STREAM_TIMEOUT:-300}"

jget() {
  python3 -c "import json,sys
d=json.load(sys.stdin)
cur=d
for p in sys.argv[1].split('.'):
  cur = cur.get(p) if isinstance(cur, dict) else None
print('' if cur is None else cur)" "$1"
}

pass() { echo "PASS $1 — $2" | tee -a "$OUT"; }
fail() { echo "FAIL $1 — $2" | tee -a "$OUT"; exit 1; }
info() { echo "INFO $1 — $2" | tee -a "$OUT"; }

{
  echo "# U8 Agent smoke batch $TS"
  echo "UTC $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "phone=$PHONE"
  echo
} > "$OUT"

# --- auth (password login; register needs captcha when mode=hcaptcha) ---
CAP=$(curl -sS "$API/captcha")
MODE=$(printf "%s" "$CAP" | jget mode)
info AUTH "captcha mode=$MODE"

LOGIN=$(curl -sS -X POST "$API/auth/login" -H "Content-Type: application/json" \
  -d "{\"phone\":\"$PHONE\",\"password\":\"$PASS\"}")
TOKEN=$(printf "%s" "$LOGIN" | jget data.token)
[[ -z "$TOKEN" ]] && TOKEN=$(printf "%s" "$LOGIN" | jget token)
[[ -n "$TOKEN" ]] || fail AUTH "login: $LOGIN"
pass AUTH "login phone=$PHONE token_len=${#TOKEN}"

AUTH=(-H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json")

# --- provider ---
PROV=$(curl -sS "$API/agent/provider")
MODEL=$(printf "%s" "$PROV" | jget model)
[[ -n "$MODEL" ]] || fail PROVIDER "empty: $PROV"
pass PROVIDER "model=$MODEL"

# --- create conversation ---
CREATE=$(curl -sS -X POST "$API/agent/conversations" "${AUTH[@]}" \
  -d "{\"title\":\"U8烟测$TS\",\"thinkMode\":false}")
CID=$(printf "%s" "$CREATE" | jget id)
[[ -n "$CID" ]] || CID=$(printf "%s" "$CREATE" | jget data.id)
[[ -n "$CID" ]] || fail CRUD "create: $CREATE"
pass CRUD-CREATE "id=$CID"

# --- list ---
LIST=$(curl -sS "$API/agent/conversations" "${AUTH[@]}")
COUNT=$(printf "%s" "$LIST" | python3 -c "import json,sys; d=json.load(sys.stdin); c=d.get('conversations') or d.get('data',{}).get('conversations') or []; print(len(c))")
[[ "$COUNT" -ge 1 ]] || fail CRUD-LIST "count=$COUNT raw=$(printf "%s" "$LIST" | head -c 300)"
pass CRUD-LIST "count=$COUNT"

# --- get detail ---
DETAIL=$(curl -sS "$API/agent/conversations/$CID" "${AUTH[@]}")
DID=$(printf "%s" "$DETAIL" | jget id)
[[ "$DID" == "$CID" ]] || DID=$(printf "%s" "$DETAIL" | jget data.id)
[[ "$DID" == "$CID" ]] || fail CRUD-GET "detail id mismatch: $DETAIL"
pass CRUD-GET "messages=$(printf "%s" "$DETAIL" | python3 -c "import json,sys; d=json.load(sys.stdin); m=d.get('messages') or d.get('data',{}).get('messages') or []; print(len(m))")"

# --- SSE stream (simple reply, no tools) ---
STREAM_FILE="/tmp/ninewood-u8-stream-$TS.txt"
info STREAM "POST …/stream (timeout=${STREAM_TIMEOUT}s) thinkMode=false"
set +e
curl -sS -N --max-time "$STREAM_TIMEOUT" -X POST "$API/agent/conversations/$CID/stream" \
  "${AUTH[@]}" \
  -H "Accept: text/event-stream" \
  -d "{\"message\":\"用一句话介绍九木平台，不要调用任何工具。\",\"thinkMode\":false,\"accessMode\":\"approval\"}" \
  > "$STREAM_FILE" 2>/tmp/ninewood-u8-stream-err-$TS.txt
STREAM_RC=$?
set -e

BYTES=$(wc -c < "$STREAM_FILE" | tr -d ' ')
EVENTS=$(grep -c '^event:' "$STREAM_FILE" || true)
HAS_DONE=$(grep -c 'event: *done\|\[DONE\]\|event: *end' "$STREAM_FILE" || true)
HAS_DELTA=$(grep -c 'event: *delta\|event: *token\|event: *message\|event: *content\|event: *think' "$STREAM_FILE" || true)
HAS_ERROR=$(grep -ci 'event: *error\|\"error\"' "$STREAM_FILE" || true)
SAMPLE=$(head -c 500 "$STREAM_FILE" | tr '\n' ' ')

echo "stream_rc=$STREAM_RC bytes=$BYTES events=$EVENTS done=$HAS_DONE delta=$HAS_DELTA error_hits=$HAS_ERROR" >> "$OUT"
echo "stream_sample=$SAMPLE" >> "$OUT"

if [[ "$STREAM_RC" -ne 0 && "$BYTES" -eq 0 ]]; then
  fail STREAM "curl_rc=$STREAM_RC err=$(cat /tmp/ninewood-u8-stream-err-$TS.txt) empty body"
fi
if [[ "$BYTES" -lt 10 ]]; then
  fail STREAM "too short bytes=$BYTES sample=$SAMPLE"
fi
if [[ "$HAS_ERROR" -gt 0 && "$HAS_DELTA" -eq 0 ]]; then
  fail STREAM "error without content: $SAMPLE"
fi
pass STREAM "bytes=$BYTES events=$EVENTS delta=$HAS_DELTA done=$HAS_DONE rc=$STREAM_RC"

# Event type histogram
info STREAM-EVENTS "$(python3 - <<PY
import re
from collections import Counter
text=open("$STREAM_FILE").read()
ev=re.findall(r'(?m)^event:\s*(\S+)', text)
print(dict(Counter(ev)) if ev else 'no event: lines; first 200 chars='+repr(text[:200]))
PY
)"

# --- second stream: try to trigger write tool pending (create demand) ---
STREAM2="/tmp/ninewood-u8-stream2-$TS.txt"
info WRITE "attempt create_demand under accessMode=approval"
set +e
curl -sS -N --max-time "$STREAM_TIMEOUT" -X POST "$API/agent/conversations/$CID/stream" \
  "${AUTH[@]}" \
  -H "Accept: text/event-stream" \
  -d "{\"message\":\"请用工具帮我创建一个需求：标题「U8助手烟测勿执行$TS」，描述「自动化检验，请弹出确认不要自动创建」，品类日常服务，最低价100。必须调用 create_demand 工具。\",\"thinkMode\":false,\"accessMode\":\"approval\"}" \
  > "$STREAM2" 2>/tmp/ninewood-u8-stream2-err-$TS.txt
STREAM2_RC=$?
set -e

PENDING=$(grep -c 'tool_pending\|tool-pending\|pending_tool' "$STREAM2" || true)
TOOL_RESULT=$(grep -c 'tool_result\|tool-result' "$STREAM2" || true)
BYTES2=$(wc -c < "$STREAM2" | tr -d ' ')
echo "write_stream_rc=$STREAM2_RC bytes=$BYTES2 pending_hits=$PENDING tool_result_hits=$TOOL_RESULT" >> "$OUT"
echo "write_sample=$(head -c 800 "$STREAM2" | tr '\n' ' ')" >> "$OUT"
info WRITE-EVENTS "$(python3 - <<PY
import re
from collections import Counter
text=open("$STREAM2").read()
ev=re.findall(r'(?m)^event:\s*(\S+)', text)
print(dict(Counter(ev)) if ev else 'no event: lines; first 400='+repr(text[:400]))
# extract tool names if present
names=re.findall(r'\"name\"\s*:\s*\"([^\"]+)\"', text)
print('tool_names=', sorted(set(names))[:20])
PY
)"

if [[ "$PENDING" -gt 0 ]]; then
  pass WRITE-PENDING "tool_pending seen hits=$PENDING"
  TOOL_CALL_ID=$(python3 - <<PY
import re, json
text=open("$STREAM2").read()
m=re.search(r'event:\s*tool_pending\s*\ndata:\s*(\{.*\})', text)
if not m:
  print("")
else:
  print(json.loads(m.group(1)).get("id",""))
PY
)
  if [[ -n "$TOOL_CALL_ID" ]]; then
    REJECT=$(curl -sS -X POST "$API/agent/conversations/$CID/approve-tool" "${AUTH[@]}" \
      -d "{\"toolCallId\":\"$TOOL_CALL_ID\",\"approved\":false}")
    echo "reject_raw=$REJECT" >> "$OUT"
    pass WRITE-REJECT "toolCallId=$TOOL_CALL_ID raw=$(printf "%s" "$REJECT" | head -c 200)"
  else
    info WRITE-REJECT "could not parse toolCallId"
  fi
else
  info WRITE-PENDING "no tool_pending in stream (model may have refused tools); bytes=$BYTES2 — App U8 still needs hand-check"
fi

# --- delete conversation ---
DEL=$(curl -sS -X DELETE "$API/agent/conversations/$CID" "${AUTH[@]}")
pass CRUD-DELETE "raw=$(printf "%s" "$DEL" | head -c 120)"

echo
echo "Evidence: $OUT"
echo "Stream1: $STREAM_FILE"
echo "Stream2: $STREAM2"
