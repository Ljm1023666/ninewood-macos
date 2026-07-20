#!/usr/bin/env python3
"""Deterministic reply for lone '?' so Work does not re-run search_demands."""
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


def install_module() -> None:
    source = HERE / "question-mark-follow-up.ts"
    target = ROOT / "src/services/agent/question-mark-follow-up.ts"
    if target.exists():
        backup(target)
    shutil.copy2(source, target)
    print(f"installed: {target}")


def patch_executor() -> None:
    path = ROOT / "src/services/agent/executor.ts"
    text = path.read_text(encoding="utf-8")
    backup(path)
    if "isQuestionMarkFollowUp" in text:
        print("already patched: question-mark follow-up")
        return

    text = text.replace(
        "import { isCapabilityQuery, CAPABILITY_REPLY } from './capability-query.js';",
        "import { isCapabilityQuery, CAPABILITY_REPLY } from './capability-query.js';\n"
        "import {\n"
        "  isQuestionMarkFollowUp,\n"
        "  QUESTION_MARK_FOLLOW_UP_REPLY,\n"
        "} from './question-mark-follow-up.js';",
    )

    # Insert after capability query block
    capability_block_end = """      send('done', 'ok');
      return;
    }

    // 纯「打开第 N」且会话内已有工作集 → 确定性导航，不调用 LLM"""
    insert = """      send('done', 'ok');
      return;
    }

    // 单独「?」：指向上轮结果，禁止重新搜索刷屏
    if (!chatMode && isQuestionMarkFollowUp(message)) {
      send('text', { delta: QUESTION_MARK_FOLLOW_UP_REPLY });
      await addMessage({
        conversationId,
        role: 'assistant',
        content: QUESTION_MARK_FOLLOW_UP_REPLY,
      });
      send('done', 'ok');
      return;
    }

    // 纯「打开第 N」且会话内已有工作集 → 确定性导航，不调用 LLM"""
    if capability_block_end not in text:
        raise RuntimeError("capability block end not found")
    text = text.replace(capability_block_end, insert, 1)
    path.write_text(text, encoding="utf-8")
    print(f"patched: {path}")


def main() -> None:
    install_module()
    patch_executor()
    print("question-mark follow-up patch applied")


if __name__ == "__main__":
    main()
