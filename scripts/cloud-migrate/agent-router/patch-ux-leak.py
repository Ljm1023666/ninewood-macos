#!/usr/bin/env python3
"""Fix Work UX: strip leaked <tool_call> text; deterministic navigate intents."""
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


def install_modules() -> None:
    for name in (
        "sanitize-assistant-text.ts",
        "navigate-intent.ts",
        "question-mark-follow-up.ts",
    ):
        source = HERE / name
        target = ROOT / "src/services/agent" / name
        if target.exists():
            backup(target)
        shutil.copy2(source, target)
        print(f"installed: {target}")


def patch_executor() -> None:
    path = ROOT / "src/services/agent/executor.ts"
    text = path.read_text(encoding="utf-8")
    backup(path)

    if "createToolCallStripper" not in text:
        text = text.replace(
            "import {\n"
            "  isQuestionMarkFollowUp,\n"
            "  QUESTION_MARK_FOLLOW_UP_REPLY,\n"
            "} from './question-mark-follow-up.js';",
            "import {\n"
            "  isQuestionMarkFollowUp,\n"
            "  QUESTION_MARK_FOLLOW_UP_REPLY,\n"
            "} from './question-mark-follow-up.js';\n"
            "import {\n"
            "  createToolCallStripper,\n"
            "  sanitizeAssistantText,\n"
            "} from './sanitize-assistant-text.js';\n"
            "import {\n"
            "  extractNavigateTarget,\n"
            "  resolveNavigateTarget,\n"
            "} from './navigate-intent.js';",
        )
        # If question-mark import missing, add after capability
        if "createToolCallStripper" not in text:
            text = text.replace(
                "import { isCapabilityQuery, CAPABILITY_REPLY } from './capability-query.js';",
                "import { isCapabilityQuery, CAPABILITY_REPLY } from './capability-query.js';\n"
                "import {\n"
                "  isQuestionMarkFollowUp,\n"
                "  QUESTION_MARK_FOLLOW_UP_REPLY,\n"
                "} from './question-mark-follow-up.js';\n"
                "import {\n"
                "  createToolCallStripper,\n"
                "  sanitizeAssistantText,\n"
                "} from './sanitize-assistant-text.js';\n"
                "import {\n"
                "  extractNavigateTarget,\n"
                "  resolveNavigateTarget,\n"
                "} from './navigate-intent.js';",
            )

    # Deterministic navigate after question-mark block
    if "extractNavigateTarget(message)" not in text:
        nav_anchor = """    // 单独「?」：指向上轮结果，禁止重新搜索刷屏
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
        nav_insert = """    // 单独「?」：指向上轮结果，禁止重新搜索刷屏
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

    // 「打开/跳转 XX」：确定性 navigate，避免模型把 <tool_call> 写进气泡
    if (!chatMode) {
      const navTarget = extractNavigateTarget(message)
      const route = navTarget ? resolveNavigateTarget(navTarget) : null
      if (route) {
        const quietSend: EventSender = (event, data) => {
          if (event === 'text') return
          send(event, data)
        }
        const combined = await processToolInvocations(
          [{ name: 'navigate_to', arguments: { path: route.path, page: route.title } }],
          { ...toolCtx, send: quietSend },
        )
        const navMsg = `已打开${route.title}。`
        send('text', { delta: navMsg })
        await addMessage({
          conversationId,
          role: 'assistant',
          content: navMsg,
          toolCalls:
            combined.storedCalls.length > 0
              ? combined.storedCalls.map((c) => ({
                  id: c.id,
                  name: c.name,
                  arguments: c.arguments,
                  status: c.status,
                  steps: c.steps,
                  result: c.result,
                  data: c.data,
                  success: c.success,
                }))
              : undefined,
        })
        send('done', 'ok')
        return
      }
    }

    // 纯「打开第 N」且会话内已有工作集 → 确定性导航，不调用 LLM"""
        if nav_anchor not in text:
            raise RuntimeError("question-mark anchor missing for navigate intent")
        text = text.replace(nav_anchor, nav_insert, 1)

    # Wrap text deltas with tool-call stripper in runAgentRound
    if "toolCallStripper" not in text:
        old_delta = """  let streamedText = ''

  const { fullContent, thinkLinesSent } = await readSSEStream(reader, {
    onTextDelta: (delta) => {
      if (thinkStripper) {
        const cleaned = thinkStripper.feed(delta)
        if (cleaned) {
          send('text', { delta: cleaned })
          streamedText += cleaned
        }
      } else {
        send('text', { delta })
        streamedText += delta
      }
    },"""
        new_delta = """  let streamedText = ''
  const toolCallStripper = createToolCallStripper()

  const { fullContent, thinkLinesSent } = await readSSEStream(reader, {
    onTextDelta: (delta) => {
      const strip = (chunk: string) => toolCallStripper.feed(chunk)
      if (thinkStripper) {
        const cleaned = thinkStripper.feed(delta)
        if (cleaned) {
          const safe = strip(cleaned)
          if (safe) {
            send('text', { delta: safe })
            streamedText += safe
          }
        }
      } else {
        const safe = strip(delta)
        if (safe) {
          send('text', { delta: safe })
          streamedText += safe
        }
      }
    },"""
        if old_delta not in text:
            raise RuntimeError("runAgentRound onTextDelta block not found")
        text = text.replace(old_delta, new_delta, 1)

        # flush stripper into content assignment
        text = text.replace(
            "  const content = thinkStripper ? streamedText : (streamedText || fullContent)\n  return { content, toolCalls }",
            "  const flushedTools = toolCallStripper.flush()\n"
            "  if (flushedTools) {\n"
            "    send('text', { delta: flushedTools })\n"
            "    streamedText += flushedTools\n"
            "  }\n"
            "  const content = sanitizeAssistantText(\n"
            "    thinkStripper ? streamedText : (streamedText || fullContent),\n"
            "  )\n"
            "  return { content, toolCalls }",
            1,
        )

    path.write_text(text, encoding="utf-8")
    print(f"patched: {path}")


def main() -> None:
    install_modules()
    patch_executor()
    print("ux-leak patch applied")


if __name__ == "__main__":
    main()
