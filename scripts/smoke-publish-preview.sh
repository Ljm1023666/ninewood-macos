#!/usr/bin/env bash
# Smoke-test macOS publish hub + demand/service workspaces via design preview.
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/docs/qa-screenshots/publish-smoke}"
APP="$HOME/Library/Developer/Xcode/DerivedData/ninewood-macos-clpzklqbduzcmifmmhgonlaiammf/Build/Products/Debug/ninewood-macos.app"

cd "$ROOT"
mkdir -p "$OUT"

echo "== domain tests =="
xcrun swift test --filter PublishWorkspaceRulesSmokeTests

echo "== build app =="
xcodebuild -project ninewood-macos.xcodeproj \
  -scheme ninewood-macos \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build CODE_SIGNING_ALLOWED=NO >/tmp/ninewood-publish-build.log

APP_BUILT="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/Build/Products/Debug/ninewood-macos.app' ! -path '*/Index.noindex/*' -print -quit 2>/dev/null || true)"
if [[ -n "$APP_BUILT" ]]; then APP="$APP_BUILT"; fi
BIN="$APP/Contents/MacOS/ninewood-macos"
if [[ ! -x "$BIN" ]]; then
  echo "missing binary: $BIN" >&2
  exit 1
fi
echo "APP=$APP"

killall ninewood-macos 2>/dev/null || true
sleep 0.5

launch_preview() {
  local slug="$1"
  local shot="$2"
  killall ninewood-macos 2>/dev/null || true
  sleep 0.4
  NINEWOOD_DESIGN_PREVIEW="$slug" open -n "$APP" --args "-$slug-design-preview"
  # wait for window
  for _ in $(seq 1 30); do
    if osascript -e 'tell application "System Events" to (name of processes) contains "ninewood-macos"' >/dev/null; then
      sleep 1.2
      break
    fi
    sleep 0.2
  done
  sleep 1.5
  # bring front + capture
  osascript <<'EOF' >/dev/null
tell application "ninewood-macos" to activate
delay 0.4
EOF
  screencapture -x -l "$(osascript -e 'tell application "ninewood-macos" to id of window 1' 2>/dev/null || true)" "$OUT/$shot.png" 2>/dev/null \
    || screencapture -x "$OUT/$shot.png"
  echo "captured $OUT/$shot.png"
}

launch_preview "publish" "05-publish-hub"
launch_preview "demand-create" "05a-demand-workspace"
launch_preview "service-create" "05b-service-workspace"

# Hub → start AI organize interaction
killall ninewood-macos 2>/dev/null || true
sleep 0.4
NINEWOOD_DESIGN_PREVIEW=publish open -n "$APP" --args "-publish-design-preview"
sleep 2.2
osascript <<'EOF'
tell application "ninewood-macos" to activate
delay 0.5
tell application "System Events"
  tell process "ninewood-macos"
    set frontmost to true
    delay 0.3
    -- Click primary CTA by accessibility / button title
    try
      click (first button of window 1 whose description contains "开始用 AI 整理" or name contains "开始用 AI 整理")
    on error
      try
        click (first button of window 1 whose value of attribute "AXIdentifier" is "publish-hub-start-ai")
      on error
        -- fallback: click approximate bottom-right CTA area is unreliable; skip
      end try
    end try
  end tell
end tell
delay 1.2
EOF
screencapture -x "$OUT/05-publish-hub-after-cta.png"
echo "captured $OUT/05-publish-hub-after-cta.png"

# Demand workspace preview interaction: type + Speed + send (frontendPreview path)
killall ninewood-macos 2>/dev/null || true
sleep 0.4
NINEWOOD_DESIGN_PREVIEW=demand-create open -n "$APP" --args "-demand-create-design-preview"
sleep 2.2
osascript <<'EOF'
tell application "ninewood-macos" to activate
delay 0.6
tell application "System Events"
  tell process "ninewood-macos"
    set frontmost to true
    delay 0.4
    -- Focus composer: keystroke into front window
    keystroke "测试需求：浦东修空调，预算200-350，希望今天上门"
    delay 0.3
    key code 36 -- return / send via onSubmit
    delay 1.0
  end tell
end tell
EOF
screencapture -x "$OUT/05a-demand-after-send.png"
echo "captured $OUT/05a-demand-after-send.png"

killall ninewood-macos 2>/dev/null || true
echo "== done: $OUT =="
ls -la "$OUT"
