#!/bin/bash
# 登录后自动恢复 Tailscale Serve（每 5 分钟检查一次，未配置则拉起）
set -euo pipefail

TS="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
MARKER="/tmp/ollama-tailnet-serve-configured"

[[ -x "$TS" ]] || exit 0
"$TS" status >/dev/null 2>&1 || exit 0
curl -sf http://127.0.0.1:11435/api/tags >/dev/null 2>&1 || exit 0

if "$TS" serve status 2>/dev/null | grep -q "127.0.0.1:11435"; then
  touch "$MARKER"
  exit 0
fi

"$TS" serve reset 2>/dev/null || true
"$TS" serve --bg --https=443 http://127.0.0.1:11435
echo "$(date -Iseconds) serve restored" >> /tmp/ollama-tailnet-serve.log
