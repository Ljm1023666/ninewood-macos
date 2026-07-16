#!/bin/bash
# 查看本机 Ollama + Tailscale 链路状态

TS="/Applications/Tailscale.app/Contents/MacOS/Tailscale"

check() {
  if eval "$2" >/dev/null 2>&1; then
    printf "  ✅ %s\n" "$1"
  else
    printf "  ❌ %s\n" "$1"
  fi
}

echo "=== Tailscale ==="
if [[ -x "$TS" ]]; then
  "$TS" status 2>/dev/null | head -5 || echo "  未连接"
  echo ""
  "$TS" serve status 2>/dev/null || echo "  Serve 未配置"
else
  echo "  未安装 Tailscale"
fi

echo ""
echo "=== 本机服务 ==="
check "Ollama (11434)" "curl -sf http://127.0.0.1:11434/api/tags"
check "Host 代理 (11435)" "curl -sf http://127.0.0.1:11435/api/tags"
check "Serve HTTPS 入口" "curl -sf https://macbook-pro.tail1d8190.ts.net/v1/models"

echo ""
echo "=== 进程 ==="
lsof -i :11434 -i :11435 2>/dev/null | grep LISTEN || echo "  (无监听)"
