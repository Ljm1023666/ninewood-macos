#!/usr/bin/env bash
# Domain + app build with fixed full Xcode (never Command Line Tools).
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "DEVELOPER_DIR=$DEVELOPER_DIR"
xcrun --find swift
xcrun swift test
xcodebuild -project ninewood-macos.xcodeproj \
  -scheme ninewood-macos \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build CODE_SIGNING_ALLOWED=NO SWIFT_STRICT_CONCURRENCY=complete
