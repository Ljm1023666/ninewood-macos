#!/usr/bin/env bash
# AX smoke: publish hub CTA → workspace; demand preview send → right-panel fill.
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/../ninewood-llm-lab/runs/publish-smoke-ax}"
DRIVER="$ROOT/scripts/publish-ui-driver.swift"
STAGE="/tmp/ninewood-preview-app"
cd "$ROOT"
mkdir -p "$OUT"

xcodebuild -project ninewood-macos.xcodeproj \
  -scheme ninewood-macos -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build CODE_SIGNING_ALLOWED=NO >/tmp/ninewood-publish-ax-build.log

APP="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/Build/Products/Debug/ninewood-macos.app' ! -path '*/Index.noindex/*' -print -quit)"
echo "APP=$APP"

# Stage a copy so a stuck Xcode debug shell (SX) does not steal AX focus.
pkill -9 -f "$STAGE" 2>/dev/null || true
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/ninewood-macos.app"
BIN="$STAGE/ninewood-macos.app/Contents/MacOS/ninewood-macos"

ocr_check() {
  local png="$1" expect="$2"
  swift -e '
import Vision
import AppKit
let path = CommandLine.arguments[1]
let expect = CommandLine.arguments[2]
guard let img = NSImage(contentsOfFile: path), let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff), let cg = rep.cgImage else { fatalError("img") }
let req = VNRecognizeTextRequest()
req.recognitionLanguages = ["zh-Hans", "en-US"]
req.recognitionLevel = .accurate
try VNImageRequestHandler(cgImage: cg).perform([req])
let s = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " | ")
let keys = expect.split(separator: ",").map(String.init)
let ok = keys.allSatisfy { s.contains($0) }
print(ok ? "OCR_OK" : "OCR_MISS")
print(String(s.prefix(280)))
exit(ok ? 0 : 1)
' "$png" "$expect"
}

FAIL=0

echo "===== Hub CTA ====="
pkill -9 -f "$STAGE" 2>/dev/null || true
sleep 0.3
NINEWOOD_DESIGN_PREVIEW=publish "$BIN" >/tmp/nw-ax-hub.log 2>&1 &
sleep 4
if swift "$DRIVER" hubCTA "$OUT/02-after-cta.png"; then
  echo "PASS hub CTA AX"
  ocr_check "$OUT/02-after-cta.png" "需求工作区,Speed" || FAIL=1
else
  echo "FAIL hub CTA"
  FAIL=1
fi

echo "===== Demand preview send ====="
pkill -9 -f "$STAGE" 2>/dev/null || true
sleep 0.4
# refresh staged copy (avoid nested cp if prior run left debris)
rm -rf "$STAGE" && mkdir -p "$STAGE" && cp -R "$APP" "$STAGE/ninewood-macos.app"
BIN="$STAGE/ninewood-macos.app/Contents/MacOS/ninewood-macos"
NINEWOOD_DESIGN_PREVIEW=demand-create "$BIN" >/tmp/nw-ax-demand.log 2>&1 &
sleep 4
if swift "$DRIVER" demandSend "$OUT/04-demand-after-send.png"; then
  echo "PASS demand send AX"
  ocr_check "$OUT/04-demand-after-send.png" "预览模式,日常" || FAIL=1
else
  echo "FAIL demand send"
  FAIL=1
fi

pkill -9 -f "$STAGE" 2>/dev/null || true
ls -la "$OUT"/02-after-cta.png "$OUT"/04-demand-after-send.png 2>/dev/null || true
exit "$FAIL"
