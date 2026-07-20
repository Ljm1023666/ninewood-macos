#!/usr/bin/env python3
"""Runtime patches for Live API quality: narration cap, capability query, search header."""
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


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        if new.strip() in text:
            print(f"already patched: {path.name}")
            return
        raise RuntimeError(f"pattern not found in {path}: {old[:80]!r}")
    backup(path)
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"patched: {path}")


def install_modules() -> None:
    for name in ("list-narration-cap.ts", "capability-query.ts"):
        source = HERE / name
        target = ROOT / "src/services/agent" / name
        if not source.is_file():
            raise RuntimeError(f"missing: {source}")
        if target.exists():
            backup(target)
        shutil.copy2(source, target)
        print(f"installed: {target}")


def patch_tool_runner() -> None:
    path = ROOT / "src/services/agent/tool-runner.ts"
    text = path.read_text(encoding="utf-8")
    if "capNumberedListNarration(doneStep" in text:
        print("already patched: tool-runner.ts")
        return
    backup(path)
    if "capNumberedListNarration" not in text:
        text = text.replace(
            "import { shouldEmitToolReport } from './agent-tool-synthesis.js'",
            "import { shouldEmitToolReport } from './agent-tool-synthesis.js'\n"
            "import { capNumberedListNarration } from './list-narration-cap.js'",
        )
    old = 'ctx.send(\'text\', { delta: `\\n> ${doneStep}\\n` })'
    new = """const displayStep =
      result.success && isListToolName(name) && Array.isArray(result.data)
        ? capNumberedListNarration(doneStep, 5)
        : doneStep
    ctx.send('text', { delta: `\\n> ${displayStep}\\n` })"""
    if old not in text:
        raise RuntimeError("tool-runner doneStep send not found")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"patched: {path}")


def patch_executor_capability() -> None:
    path = ROOT / "src/services/agent/executor.ts"
    text = path.read_text(encoding="utf-8")
    if "isCapabilityQuery(message)" in text:
        print("already patched: executor capability")
        return
    if "isCapabilityQuery" not in text:
        text = text.replace(
            "import { guardToolInvocations } from './search-argument-guard.js';",
            "import { guardToolInvocations } from './search-argument-guard.js';\n"
            "import { isCapabilityQuery, CAPABILITY_REPLY } from './capability-query.js';",
        )
    anchor = """    await truncateTitle(conversationId, message);

    const toolCtx = { userId, conversationId, accessMode, send };

    // 纯「打开第 N」且会话内已有工作集 → 确定性导航，不调用 LLM"""
    insert = """    await truncateTitle(conversationId, message);

    const toolCtx = { userId, conversationId, accessMode, send };

    // 能力介绍：确定性回复，避免误调 read_knowledge 或复述搜索结果
    if (!chatMode && isCapabilityQuery(message)) {
      send('text', { delta: CAPABILITY_REPLY });
      await addMessage({
        conversationId,
        role: 'assistant',
        content: CAPABILITY_REPLY,
      });
      send('done', 'ok');
      return;
    }

    // 纯「打开第 N」且会话内已有工作集 → 确定性导航，不调用 LLM"""
    if anchor not in text:
        raise RuntimeError("executor capability anchor not found")
    if "isCapabilityQuery(message)" not in text.split("纯「打开第 N」")[0]:
        text = text.replace(anchor, insert, 1)
    path.write_text(text, encoding="utf-8")
    print(f"patched: {path}")


def patch_search_header() -> None:
    path = ROOT / "src/services/agent/tools.ts"
    text = path.read_text(encoding="utf-8")
    backup(path)
    needle = "      const indexed = indexList(list)\n      const header =\n        dropped > 0\n          ? `找到 ${list.length} 个「${city.cityName || '相关'}」需求（已剔除 ${dropped} 条地域不一致）`\n          : `找到 ${list.length} 个相关需求`"
    insert = """      const indexed = indexList(list)
      const noGeoFilter =
        !city.cityName && !city.cityCode && !normalized.keyword && !filters.category
      const header =
        dropped > 0
          ? `找到 ${list.length} 个「${city.cityName || '相关'}」需求（已剔除 ${dropped} 条地域不一致）`
          : noGeoFilter
            ? `未指定城市，正在搜索全国公开需求（共 ${list.length} 条）`
            : `找到 ${list.length} 个相关需求`"""
    if needle not in text:
        if "noGeoFilter" in text:
            print("already patched: tools.ts header")
            return
        raise RuntimeError("tools.ts search header block not found")
    path.write_text(text.replace(needle, insert, 1), encoding="utf-8")
    print(f"patched: {path}")


def main() -> None:
    install_modules()
    patch_tool_runner()
    patch_executor_capability()
    patch_search_header()
    print("live-api-quality patch applied")


if __name__ == "__main__":
    main()
