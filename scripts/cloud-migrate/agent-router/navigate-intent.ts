/** Deterministic page navigation for「打开/跳转 XX」without LLM. */

const NAV_RE =
  /(?:帮我)?(?:打开|跳转(?:到)?|去|前往)(?:一下)?(.+?)(?:页面|界面|页)?$/

const KNOWN: Record<string, { path: string; title: string }> = {
  首页: { path: '/', title: '首页' },
  发现页: { path: '/discover', title: '发现' },
  发现: { path: '/discover', title: '发现' },
  发布需求: { path: '/demands/create', title: '发布需求' },
  订单: { path: '/orders', title: '订单' },
  消息: { path: '/messages', title: '消息' },
  卡池: { path: '/card-pool', title: '卡池' },
  认证中心: { path: '/cert-center', title: '认证中心' },
  认证: { path: '/cert-center', title: '认证中心' },
  圈子: { path: '/circles', title: '圈子' },
  自然回: { path: '/loops', title: '自然回' },
  找人: { path: '/search', title: '找人' },
  个人主页: { path: '/profile', title: '个人主页' },
  我的: { path: '/profile', title: '个人主页' },
  AI助手: { path: '/agent', title: 'AI 助手' },
}

const ALIASES: Record<string, string> = {
  发人: '找人',
  搜人: '找人',
  搜索用户: '找人',
  找人页: '找人',
  发布: '发布需求',
  发需求: '发布需求',
  个人中心: '个人主页',
  主页: '首页',
  页面中心: '首页',
}

function normalize(raw: string): string {
  return raw
    .trim()
    .replace(/[「」『』【】\[\]()（）?\？!！\s]/g, '')
    .replace(/(页面|界面|模块|功能)$/u, '')
}

export function extractNavigateTarget(message: string): string | null {
  const compact = message.replace(/\s/g, '')
  const m = compact.match(NAV_RE)
  if (!m?.[1]) return null
  return normalize(m[1])
}

export function resolveNavigateTarget(
  raw: string,
): { path: string; title: string } | null {
  const key = normalize(raw)
  if (!key) return null
  if (KNOWN[key]) return KNOWN[key]
  if (ALIASES[key] && KNOWN[ALIASES[key]]) return KNOWN[ALIASES[key]]
  for (const [alias, target] of Object.entries(ALIASES)) {
    if (key.includes(alias) || alias.includes(key)) {
      return KNOWN[target] ?? null
    }
  }
  for (const [name, route] of Object.entries(KNOWN)) {
    if (key.includes(name) || name.includes(key)) return route
  }
  return null
}

export function isNavigateIntent(message: string): boolean {
  return extractNavigateTarget(message) != null
}
