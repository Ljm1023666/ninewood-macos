#!/usr/bin/env python3
"""Ensure Prisma DemandStatus includes DRAFT (PG enum already has it).

Without this, any Demand row with status=DRAFT makes prisma.demand.findMany()
fail with: Value 'DRAFT' not found in enum 'DemandStatus'.
"""
from __future__ import annotations

import shutil
import subprocess
from datetime import datetime
from pathlib import Path

ROOT = Path("/opt/ninewood/server")
SCHEMA = ROOT / "prisma/schema.prisma"
STAMP = datetime.now().strftime("%Y%m%d-%H%M%S")

OLD = """enum DemandStatus {
  PENDING
  ACTIVE
  FROZEN
  IN_PROGRESS
  COMPLETED
  CLOSED
  WITHDRAWN
}"""

NEW = """enum DemandStatus {
  PENDING
  ACTIVE
  FROZEN
  IN_PROGRESS
  COMPLETED
  CLOSED
  WITHDRAWN
  DRAFT
}"""


def main() -> None:
    text = SCHEMA.read_text(encoding="utf-8")
    if "DRAFT" in text.split("enum DemandStatus", 1)[-1].split("}", 1)[0]:
        print("already has DRAFT in DemandStatus")
    else:
        if OLD not in text:
            raise SystemExit("DemandStatus block not found / unexpected shape")
        bak = SCHEMA.with_suffix(SCHEMA.suffix + f".bak-draft-{STAMP}")
        shutil.copy2(SCHEMA, bak)
        SCHEMA.write_text(text.replace(OLD, NEW, 1), encoding="utf-8")
        print(f"updated {SCHEMA} (backup {bak})")

    subprocess.check_call(["npx", "prisma", "generate"], cwd=ROOT)
    subprocess.check_call(["pm2", "restart", "ninewood"])
    print("done")


if __name__ == "__main__":
    main()
