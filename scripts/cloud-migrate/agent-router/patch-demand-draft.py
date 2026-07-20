#!/usr/bin/env python3
"""Install deterministic multi-turn demand draft handling into Work executor."""
from __future__ import annotations

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


def install(name: str) -> None:
    source = HERE / name
    target = ROOT / "src/services/agent" / name
    if not source.is_file():
        raise RuntimeError(f"missing module: {source}")
    if target.exists():
        backup(target)
    shutil.copy2(source, target)
    print(f"installed: {target}")


def patch_executor() -> None:
    path = ROOT / "src/services/agent/executor.ts"
    text = path.read_text(encoding="utf-8")
    import_line = (
        "import { buildDemandDraft, demandDraftFollowUp } "
        "from './demand-draft.js';"
    )
    if import_line not in text:
        anchor = "import { isListToolName } from './working-set.js';"
        if anchor not in text:
            raise RuntimeError("executor import anchor not found")
        text = text.replace(anchor, anchor + "\n" + import_line, 1)

    marker = "// 发布需求多轮草稿：确定性补槽，禁止纯数字误触发搜索"
    if marker in text:
        path.write_text(text, encoding="utf-8")
        print("already patched: executor demand draft")
        return

    anchor = "    // 能力介绍：确定性回复，避免误调 read_knowledge 或复述搜索结果"
    if anchor not in text:
        raise RuntimeError("executor demand draft anchor not found")
    block = f"""    {marker}
    if (!chatMode) {{
      const draft = buildDemandDraft(history ?? [], message)
      if (draft.active && !draft.ready) {{
        const reply = demandDraftFollowUp(draft)
        send('text', {{ delta: reply }})
        await addMessage({{
          conversationId,
          role: 'assistant',
          content: reply,
        }})
        send('done', 'ok')
        return
      }}
    }}

"""
    backup(path)
    path.write_text(text.replace(anchor, block + anchor, 1), encoding="utf-8")
    print(f"patched: {path}")


def main() -> None:
    install("demand-draft.ts")
    install("sanitize-assistant-text.ts")
    patch_executor()
    print("demand draft patch applied")


if __name__ == "__main__":
    main()
