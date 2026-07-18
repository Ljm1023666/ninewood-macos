#!/usr/bin/env python3
from pathlib import Path

ROOT = Path("/opt/ninewood/server")

matcher = ROOT / "src/services/agent/capability-matcher.ts"
s = matcher.read_text()
old = """function signalMatches(signal: string, utterance: string): boolean {
  const s = normalize(signal);
  const u = normalize(utterance);
  if (!s) return false;
  return u.includes(s);
}"""
new = """function signalMatches(signal: string, utterance: string): boolean {
  const s = normalize(signal);
  const u = normalize(utterance);
  if (!s) return false;
  // intent_signals 中的 .* 是有序通配符，不应被当成普通文本。
  if (s.includes('.*')) {
    let cursor = 0
    for (const part of s.split('.*').filter(Boolean)) {
      const index = u.indexOf(part, cursor)
      if (index < 0) return false
      cursor = index + part.length
    }
    return true
  }
  return u.includes(s);
}"""
if old in s:
    matcher.write_text(s.replace(old, new, 1))
    print("patched capability wildcard matching")
elif "s.includes('.*')" not in s:
    raise SystemExit("signalMatches block not found")

tools = ROOT / "src/services/agent/tools.ts"
s = tools.read_text()
old = """          cityCode: { type: 'string', description: '城市代码' },
          minPrice:"""
new = """          cityCode: { type: 'string', description: '城市代码' },
          cityName: { type: 'string', description: '中文城市名，如\"上海\"\"杭州\"' },
          minPrice:"""
if old in s:
    s = s.replace(old, new, 1)

old = """    handler: async (args, _ctx) => {
      const filters = {
        keyword: (args.keyword as string) || undefined,
        category: (args.category as string) || undefined,
        serviceType: args.serviceType as 'ONLINE' | 'OFFLINE' | undefined,
        cityCode: (args.cityCode as string) || undefined,"""
new = """    handler: async (args, _ctx) => {
      const cityName = String(args.cityName || '').trim().replace(/市$/, '')
      let cityCode = (args.cityCode as string) || undefined
      if (!cityCode && cityName) {
        const region = await safePrisma(() =>
          prisma.region.findFirst({
            where: {
              name: { contains: cityName },
              level: { in: [2, 3] },
            },
            orderBy: { level: 'desc' },
            select: { id: true, name: true },
          }),
        )
        if (!region) return fail('城市不存在', `没有识别到城市「${cityName}」`)
        cityCode = String(region.id)
      }
      const filters = {
        keyword: (args.keyword as string) || undefined,
        category: (args.category as string) || undefined,
        serviceType: args.serviceType as 'ONLINE' | 'OFFLINE' | undefined,
        cityCode,"""
if old in s:
    s = s.replace(old, new, 1)
elif "const cityName = String(args.cityName" not in s:
    raise SystemExit("search_demands handler block not found")
tools.write_text(s)
print("patched search_demands Chinese city resolution")

yaml = ROOT / "ai-knowledge/03-agent-capabilities.yaml"
s = yaml.read_text()
s = s.replace(
    "intent_signals: [搜需求, 搜索需求, 找需求, 查需求, 有没有.*需求]",
    "intent_signals: [搜需求, 搜索需求, 找需求, 查需求, 有没有.*需求, 搜.*需求, 搜索.*需求, 找.*需求, 查.*需求]",
)
yaml.write_text(s)
print("patched search intent signals")

