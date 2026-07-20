#!/usr/bin/env python3
"""Apply all Work runtime v1 patches (idempotent wrapper)."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def main() -> int:
    for name in (
        "patch-search-argument-guard.py",
        "patch-live-api-quality.py",
        "patch-sse-bloat.py",
        "patch-question-mark.py",
        "patch-demand-draft.py",
    ):
        script = HERE / name
        print(f"== {name} ==")
        rc = subprocess.run([sys.executable, str(script)], check=False).returncode
        if rc != 0:
            return rc
    print("work-runtime-v1 patches applied")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
