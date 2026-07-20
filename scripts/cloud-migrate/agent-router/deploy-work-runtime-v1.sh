#!/usr/bin/env bash
# Idempotent deploy: Work runtime v1 patches on staging/production server.
# Usage (on server): bash scripts/cloud-migrate/agent-router/deploy-work-runtime-v1.sh
set -euo pipefail

ROOT="${NW_SERVER_ROOT:-/opt/ninewood/server}"
PATCH_DIR="$ROOT/scripts/cloud-migrate/agent-router"
RELEASE="$PATCH_DIR/RELEASE-WORK-RUNTIME-v1.json"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG_DIR="$ROOT/runs/deploy"
LOG="$LOG_DIR/work-runtime-v1-$STAMP.log"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG") 2>&1

echo "== deploy work-runtime-v1 @ $STAMP =="
echo "ROOT=$ROOT"

if [[ ! -f "$RELEASE" ]]; then
  echo "missing release manifest: $RELEASE" >&2
  exit 2
fi

cd "$ROOT"

python3 "$PATCH_DIR/patch-search-argument-guard.py"
python3 "$PATCH_DIR/patch-live-api-quality.py"
python3 "$PATCH_DIR/patch-sse-bloat.py"
python3 "$PATCH_DIR/patch-question-mark.py"
python3 "$PATCH_DIR/patch-demand-draft.py"
python3 "$PATCH_DIR/patch-ux-leak.py"

echo "== vitest (guard modules) =="
cp -f "$PATCH_DIR/ux-leak.test.ts" "$ROOT/src/__tests__/ux-leak.test.ts"
cp -f "$PATCH_DIR/live-api-quality.test.ts" "$ROOT/src/__tests__/live-api-quality.test.ts" 2>/dev/null || true
cp -f "$PATCH_DIR/search-argument-guard.test.ts" "$ROOT/src/__tests__/search-argument-guard.test.ts" 2>/dev/null || true
cp -f "$PATCH_DIR/demand-draft.test.ts" "$ROOT/src/__tests__/demand-draft.test.ts"
npm test -- search-argument-guard live-api-quality ux-leak demand-draft

echo "== pm2 restart =="
pm2 restart "${NW_PM2_PROCESS:-ninewood}"

python3 - <<'PY'
import hashlib, json
from pathlib import Path
root = Path("/opt/ninewood/server")
patch = root / "scripts/cloud-migrate/agent-router"
files = [
    "search-argument-guard.ts",
    "list-narration-cap.ts",
    "capability-query.ts",
    "patch-search-argument-guard.py",
    "patch-live-api-quality.py",
    "deploy-work-runtime-v1.sh",
    "RELEASE-WORK-RUNTIME-v1.json",
]
record = {"files": {}}
for name in files:
    p = patch / name
    if p.is_file():
        record["files"][name] = hashlib.sha256(p.read_bytes()).hexdigest()
out = root / "runs/deploy/work-runtime-v1-checksums.json"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
print(f"wrote {out}")
PY

echo "== deploy complete =="
