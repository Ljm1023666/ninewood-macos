#!/bin/bash
# 断开：停止对外暴露本机 Ollama（Tailscale 账号仍在线）
set -euo pipefail

TS="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
PROXY_PLIST="$HOME/Library/LaunchAgents/com.ninewood.ollama-tailnet-proxy.plist"

echo "==> 停止 Tailscale Serve"
"$TS" serve reset 2>/dev/null || true
echo "Serve 已关闭"

echo ""
echo "==> 停止 Host 代理 (可选)"
if [[ -f "$PROXY_PLIST" ]]; then
  launchctl bootout "gui/$(id -u)" "$PROXY_PLIST" 2>/dev/null || true
  echo "代理已停止"
else
  echo "未找到代理 plist，跳过"
fi

echo ""
echo "⏸  已断开。云端 AI 将无法调用本机模型。"
echo "   Ollama 仍在本地运行；仅 Tailscale 入口已关闭。"
echo "   重新连接: ~/Desktop/九木AI-mac-连接.sh"
