#!/usr/bin/env python3
"""Shrink list-tool SSE + stop LLM post-search spam (B2 bloat / suffix_loop)."""
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
    source = HERE / "list-narration-cap.ts"
    target = ROOT / "src/services/agent/list-narration-cap.ts"
    backup(target)
    shutil.copy2(source, target)
    print(f"installed: {target}")


def patch_tool_runner() -> None:
    path = ROOT / "src/services/agent/tool-runner.ts"
    text = path.read_text(encoding="utf-8")
    backup(path)
    if "capListDataForSse" not in text:
        text = text.replace(
            "import { capNumberedListNarration } from './list-narration-cap.js'",
            "import {\n"
            "  capNumberedListNarration,\n"
            "  capListDataForSse,\n"
            "} from './list-narration-cap.js'",
        )
    old = """    ctx.send('tool_step', { id: toolCallId, name, phase: 'done', text: doneStep })
    const displayStep =
      result.success && isListToolName(name) && Array.isArray(result.data)
        ? capNumberedListNarration(doneStep, 5)
        : doneStep
    ctx.send('text', { delta: `\\n> ${displayStep}\\n` })
    ctx.send('tool_result', {
      id: toolCallId,
      name,
      success: result.success,
      data: result.data,
      error: result.error,
      message: result.message,
    })"""
    new = """    const listOk = result.success && isListToolName(name) && Array.isArray(result.data)
    const displayStep = listOk ? capNumberedListNarration(doneStep, 5) : doneStep
    const sseData = listOk ? capListDataForSse(result.data, 5) : result.data
    ctx.send('tool_step', { id: toolCallId, name, phase: 'done', text: displayStep })
    ctx.send('text', { delta: `\\n> ${displayStep}\\n` })
    ctx.send('tool_result', {
      id: toolCallId,
      name,
      success: result.success,
      data: sseData,
      error: result.error,
      message: displayStep,
    })"""
    if "capListDataForSse(result.data" in text:
        print("already patched: tool-runner sse cap")
        return
    if old not in text:
        raise RuntimeError("tool-runner block not found for sse cap")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"patched: {path}")


def patch_executor_skip_list_summary() -> None:
    path = ROOT / "src/services/agent/executor.ts"
    text = path.read_text(encoding="utf-8")
    backup(path)
    if "listNarrationDone" in text:
        print("already patched: executor list early exit")
        return

    if "isListNarrationComplete" not in text:
        # after capability-query import if present, else after guard
        if "from './capability-query.js'" in text:
            text = text.replace(
                "import { isCapabilityQuery, CAPABILITY_REPLY } from './capability-query.js';",
                "import { isCapabilityQuery, CAPABILITY_REPLY } from './capability-query.js';\n"
                "import { capNumberedListNarration, isListNarrationComplete } from './list-narration-cap.js';\n"
                "import { isListToolName } from './working-set.js';",
            )
        else:
            text = text.replace(
                "import { guardToolInvocations } from './search-argument-guard.js';",
                "import { guardToolInvocations } from './search-argument-guard.js';\n"
                "import { capNumberedListNarration, isListNarrationComplete } from './list-narration-cap.js';\n"
                "import { isListToolName } from './working-set.js';",
            )

    # After combining tool results, break if list narration is enough (no open_nth follow-up)
    anchor = """      allStoredCalls.push(...combined.storedCalls);
      allExecuted.push(...combined.executed);

      // 追加 tool 消息（OpenAI 格式，含 tool_call_id）
"""
    insert = """      allStoredCalls.push(...combined.storedCalls);
      allExecuted.push(...combined.executed);

      // 列表工具已有完整编号叙述且本轮无跟进导航 → 结束工具链，避免 LLM 二次刷屏
      const listNarrationDone =
        !followUpExtras &&
        combined.executed.some(
          (e) =>
            isListToolName(e.name) &&
            e.result.success &&
            typeof e.result.message === 'string' &&
            isListNarrationComplete(e.result.message),
        )
      if (listNarrationDone) {
        const listMsg = combined.executed
          .filter((e) => isListToolName(e.name) && e.result.success)
          .map((e) => capNumberedListNarration(String(e.result.message || ''), 5))
          .join('\\n')
        lastRoundText = listMsg
        break
      }

      // 追加 tool 消息（OpenAI 格式，含 tool_call_id）
"""
    if anchor not in text:
        raise RuntimeError("executor list early-exit anchor not found")
    text = text.replace(anchor, insert, 1)

    # Skip LLM continueWithToolResults when we already have list narration in lastRoundText
    old_sum = """    // 工具链结束后：若模型未产出正文，再补一轮无 tools 总结
    const summarizable = allExecuted
      .map((e) => e.result)
      .filter((r) => !(r.data && typeof r.data === 'object' && (r.data as { pending?: boolean }).pending));
    if (summarizable.length > 0 && !lastRoundText.trim()) {"""
    new_sum = """    // 工具链结束后：若模型未产出正文，再补一轮无 tools 总结
    // （列表搜索已在上方 early-break 填入 lastRoundText，不再二次总结）
    const summarizable = allExecuted
      .map((e) => e.result)
      .filter((r) => !(r.data && typeof r.data === 'object' && (r.data as { pending?: boolean }).pending));
    if (summarizable.length > 0 && !lastRoundText.trim()) {"""
    if old_sum in text:
        text = text.replace(old_sum, new_sum, 1)

    path.write_text(text, encoding="utf-8")
    print(f"patched: {path}")


def main() -> None:
    install_module()
    patch_tool_runner()
    patch_executor_skip_list_summary()
    print("sse-bloat patch applied")


if __name__ == "__main__":
    main()
