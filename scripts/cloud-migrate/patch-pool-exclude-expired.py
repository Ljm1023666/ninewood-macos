#!/usr/bin/env python3
from pathlib import Path

p = Path("/opt/ninewood/server/src/services/pool.service.ts")
text = p.read_text()
if "expireAt: { gte: new Date() }" in text:
    print("already patched")
    raise SystemExit(0)

needle = """    const and: any[] = [
      { deletedAt: null },
    ];

    // Stage filter
    if (params.special) {
      and.push({ stage: { in: ['active', 'compressed'] } });
    } else {
      and.push({ stage: 'active' });
    }"""

repl = """    const and: any[] = [
      { deletedAt: null },
      // 活池不展示已过期（过期进死池）
      { expireAt: { gte: new Date() } },
    ];

    // Stage filter
    if (params.special) {
      and.push({ stage: { in: ['active', 'compressed'] } });
    } else {
      and.push({ stage: 'active' });
    }"""

if needle not in text:
    raise SystemExit("needle not found")
p.write_text(text.replace(needle, repl, 1))
print("patched expireAt filter on getActive")
