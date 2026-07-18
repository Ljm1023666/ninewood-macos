#!/bin/bash
# 开启：让云端能通过 Tailscale 调用本机 Ollama
set -euo pipefail

TS="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SUPPORT="$HOME/Library/Application Support/ninewood"
PROXY_PLIST="$HOME/Library/LaunchAgents/com.ninewood.ollama-tailnet-proxy.plist"
SERVE_PLIST="$HOME/Library/LaunchAgents/com.ninewood.ollama-tailnet-serve.plist"
UID_NUM="$(id -u)"

# Desktop/下载目录受 TCC 限制，launchd 读不了；运行时拷到 Application Support
install_runtime() {
  mkdir -p "$SUPPORT"
  cp "$REPO_DIR/ollama-tailnet-proxy.py" "$SUPPORT/ollama-tailnet-proxy.py"
  cp "$REPO_DIR/ollama-tailnet-serve-boot.sh" "$SUPPORT/ollama-tailnet-serve-boot.sh"
  chmod +x "$SUPPORT/ollama-tailnet-proxy.py" "$SUPPORT/ollama-tailnet-serve-boot.sh"
  xattr -cr "$SUPPORT" 2>/dev/null || true

  cat > "$PROXY_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ninewood.ollama-tailnet-proxy</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>$SUPPORT/ollama-tailnet-proxy.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/ollama-tailnet-proxy.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/ollama-tailnet-proxy.log</string>
</dict>
</plist>
EOF

  cat > "$SERVE_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ninewood.ollama-tailnet-serve</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SUPPORT/ollama-tailnet-serve-boot.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>300</integer>
    <key>StandardOutPath</key>
    <string>/tmp/ollama-tailnet-serve.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/ollama-tailnet-serve.log</string>
</dict>
</plist>
EOF
}

OLLAMA_MODEL="${OLLAMA_MODEL:-qwen3.6:35b}"

echo "==> 1/5 检查 Tailscale"
if ! "$TS" status >/dev/null 2>&1; then
  echo "Tailscale 未连接，请先打开 Tailscale App 并登录。"
  exit 1
fi
"$TS" status | head -3

echo ""
echo "==> 2/5 检查 Ollama"
if ! curl -sf http://127.0.0.1:11434/api/tags >/dev/null; then
  echo "Ollama 未运行。请先打开 Ollama App，或执行: open -a Ollama"
  exit 1
fi
echo "Ollama OK"

echo ""
echo "==> 3/5 启动 Host 代理 (127.0.0.1:11435)"
install_runtime
launchctl bootout "gui/$UID_NUM/com.ninewood.ollama-tailnet-proxy" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$PROXY_PLIST" 2>/dev/null || true
launchctl kickstart -k "gui/$UID_NUM/com.ninewood.ollama-tailnet-proxy" 2>/dev/null || true
for _ in 1 2 3 4 5; do
  if curl -sf http://127.0.0.1:11435/api/tags >/dev/null; then
    break
  fi
  sleep 1
done
if ! curl -sf http://127.0.0.1:11435/api/tags >/dev/null; then
  echo "代理未响应，查看日志: tail /tmp/ollama-tailnet-proxy.log"
  exit 1
fi
echo "代理 OK"

echo ""
echo "==> 4/5 启动 Tailscale Serve (443 → 11435)"
launchctl bootout "gui/$UID_NUM/com.ninewood.ollama-tailnet-serve" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$SERVE_PLIST" 2>/dev/null || true
"$TS" serve reset 2>/dev/null || true
"$TS" serve --bg --https=443 http://127.0.0.1:11435
"$TS" serve status

echo ""
echo "==> 5/5 预热模型 ($OLLAMA_MODEL，keep_alive=-1 常驻)"
if curl -sf http://127.0.0.1:11434/api/ps 2>/dev/null | grep -q "$OLLAMA_MODEL"; then
  echo "模型已在内存中，跳过加载"
else
  echo "正在载入显存（首次可能需数分钟，请勿关盖）…"
  if curl -sS --max-time 900 http://127.0.0.1:11434/api/generate \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"${OLLAMA_MODEL}\",\"prompt\":\".\",\"stream\":false,\"keep_alive\":-1}" \
    -o /tmp/ollama-warmup.json; then
    if curl -sf http://127.0.0.1:11434/api/ps 2>/dev/null | grep -q "$OLLAMA_MODEL"; then
      echo "模型已常驻，后续请求无需再冷启动"
    else
      echo "预热请求已完成，但 api/ps 未看到模型；可再跑一次连接脚本"
    fi
  else
    echo "预热超时或失败（链路已通，首次对话仍会自动加载）。日志: /tmp/ollama-warmup.json"
  fi
fi

echo ""
echo "✅ 已连接。云端可访问: https://macbook-pro.tail1d8190.ts.net/v1"
echo "   保持响应：Mac 勿睡眠；模型常驻至重启/手动卸载。"
