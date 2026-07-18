#!/usr/bin/env python3
from pathlib import Path

p = Path("/opt/ninewood/server/src/services/agent/executor.ts")
text = p.read_text()

replacements = [
    (
        "    const selectedModel = model || config.aiModel;",
        "    const selectedModel = model || (thinking ? config.aiThinkModel : config.aiFastModel);",
    ),
    (
        "  const selectedModel = model || config.aiModel",
        "  const selectedModel = model || (thinking ? config.aiThinkModel : config.aiFastModel)",
    ),
]

changed = 0
for old, new in replacements:
    if old in text:
        text = text.replace(old, new)
        changed += 1

if "thinking ? config.aiThinkModel" not in text:
    raise SystemExit("patch failed: think/fast model selection missing")

p.write_text(text)
print(f"patched executor.ts ({changed} patterns, total hits={text.count('thinking ? config.aiThinkModel')})")
