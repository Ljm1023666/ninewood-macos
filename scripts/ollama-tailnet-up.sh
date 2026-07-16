#!/bin/bash
# 开启：让云端能通过 Tailscale 调用本机 Ollama
set -euo pipefail

TS="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
PROXY_PLIST="$HOME/Library/LaunchAgents/com.ninewood.ollama-tailnet-proxy.plist"
SERVE_PLIST="$HOME/Library/LaunchAgents/com.ninewood.ollama-tailnet-serve.plist"

echo "==> 1/4 检查 Tailscale"
if ! "$TS" status >/dev/null 2>&1; then
  echo "Tailscale 未连接，请先打开 Tailscale App 并登录。"
  exit 1
fi
"$TS" status | head -3

echo ""
echo "==> 2/4 检查 Ollama"
if ! curl -sf http://127.0.0.1:11434/api/tags >/dev/null; then
  echo "Ollama 未运行。请先打开 Ollama App，或执行: open -a Ollama"
  exit 1
fi
echo "Ollama OK"

echo ""
echo "==> 3/4 启动 Host 代理 (127.0.0.1:11435)"
if [[ -f "$PROXY_PLIST" ]]; then
  launchctl bootstrap "gui/$(id -u)" "$PROXY_PLIST" 2>/dev/null || true
  launchctl kickstart -k "gui/$(id -u)/com.ninewood.ollama-tailnet-proxy" 2>/dev/null || true
fi
sleep 1
if ! curl -sf http://127.0.0.1:11435/api/tags >/dev/null; then
  echo "代理未响应，查看日志: tail /tmp/ollama-tailnet-proxy.log"
  exit 1
fi
echo "代理 OK"

echo ""
echo "==> 4/4 启动 Tailscale Serve (443 → 11435)"
"$TS" serve reset 2>/dev/null || true
"$TS" serve --bg --https=443 http://127.0.0.1:11435
"$TS" serve status

echo ""
echo "✅ 已连接。云端可访问: https://macbook-pro.tail1d8190.ts.net/v1"
