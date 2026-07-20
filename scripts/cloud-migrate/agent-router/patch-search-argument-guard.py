#!/usr/bin/env python3
"""Deploy search-argument-guard on staging without the full agent-router refactor."""
from __future__ import annotations

import re
import shutil
from datetime import datetime
from pathlib import Path

ROOT = Path("/opt/ninewood/server")
HERE = Path(__file__).resolve().parent
STAMP = datetime.now().strftime("%Y%m%d-%H%M%S")


def backup(path: Path) -> None:
    dest = path.with_suffix(path.suffix + f".bak-{STAMP}")
    if path.exists() and not dest.exists():
        shutil.copy2(path, dest)


def install_module(name: str) -> None:
    source = HERE / name
    target = ROOT / "src/services/agent" / name
    if not source.is_file():
        raise RuntimeError(f"missing module: {source}")
    if target.exists():
        backup(target)
    shutil.copy2(source, target)
    print(f"installed: {target}")


def install_guard_tests() -> None:
    source = HERE / "search-argument-guard.test.ts"
    target = ROOT / "src/__tests__/search-argument-guard.test.ts"
    if not source.is_file():
        raise RuntimeError(f"missing tests: {source}")
    if target.exists():
        backup(target)
    shutil.copy2(source, target)
    print(f"installed: {target}")


def patch_executor() -> None:
    path = ROOT / "src/services/agent/executor.ts"
    text = path.read_text(encoding="utf-8")
    backup(path)

    import_line = "import { guardToolInvocations } from './search-argument-guard.js';"
    if import_line not in text:
        anchor = "import { processToolInvocations } from './tool-runner.js';"
        if anchor not in text:
            raise RuntimeError("executor import anchor missing")
        text = text.replace(
            anchor,
            anchor + "\n" + import_line,
            1,
        )

    guarded = "processToolInvocations(guardToolInvocations(invocations, message), toolCtx)"
    plain = "processToolInvocations(\n        invocations,\n        toolCtx,\n      )"
    if guarded not in text:
        if plain not in text:
            raise RuntimeError("model tool invocation boundary not found")
        text = text.replace(plain, guarded, 1)

    follow_plain = "processToolInvocations(followUps, toolCtx)"
    follow_guarded = "processToolInvocations(guardToolInvocations(followUps, message), toolCtx)"
    if follow_guarded not in text:
        if follow_plain not in text:
            raise RuntimeError("follow-up tool invocation boundary not found")
        text = text.replace(follow_plain, follow_guarded, 1)

    if "guardToolInvocations(invocations, message)" not in text:
        raise RuntimeError("refuse partial deploy: guard wiring missing after patch")

    path.write_text(text, encoding="utf-8")
    print(f"patched: {path}")


def main() -> None:
    install_module("search-argument-guard.ts")
    install_guard_tests()
    patch_executor()
    print("search-argument-guard patch applied")


if __name__ == "__main__":
    main()
