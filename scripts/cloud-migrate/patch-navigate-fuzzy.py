#!/usr/bin/env python3
"""Patch agent navigate_to: fuzzy aliases + no-spin prompt rules."""
from pathlib import Path

TOOLS = Path("/opt/ninewood/server/src/services/agent/tools.ts")
EXEC = Path("/opt/ninewood/server/src/services/agent/executor.ts")

RESOLVER = r'''
/** 口语别名 → 已知页面名（避免模型因名称不完全匹配而空转） */
const PAGE_ALIASES: Record<string, string> = {
  页面中心: '首页',
  主页: '首页',
  主界面: '首页',
  平台首页: '首页',
  发现: '发现页',
  发现服务: '发现页',
  个人中心: '个人主页',
  我的主页: '个人主页',
  我的页面: '个人主页',
  我的: '个人主页',
  资料: '个人主页',
  账号: '个人主页',
  发布: '发布需求',
  发需求: '发布需求',
  新建需求: '发布需求',
  我的订单: '订单',
  订单中心: '订单',
  聊天: '消息',
  私信: '消息',
  信箱: '消息',
  认证页: '认证中心',
  福利: '福利中心',
  激励: '激励中心',
  公益: '公益中心',
  市场: '市场分析',
  标签: '标签统计',
  钱包流水: '交易记录',
  流水: '交易记录',
  搜索用户: '找人',
  搜人: '找人',
  AI: 'AI助手',
  助手: 'AI助手',
  智能助手: 'AI助手',
  管理后台: '后台管理',
  后台: '后台管理',
}

function normalizePageName(raw: string): string {
  return raw
    .trim()
    .replace(/[「」『』【】\[\]()（）\s]/g, '')
    .replace(/(页面|界面|模块|功能)$/u, '')
}

function resolveKnownRoute(rawPage: string): { key: string; route: { path: string; title: string } } | null {
  const page = rawPage.trim()
  if (!page) return null
  if (KNOWN_ROUTES[page]) return { key: page, route: KNOWN_ROUTES[page] }

  const normalized = normalizePageName(page)
  if (KNOWN_ROUTES[normalized]) return { key: normalized, route: KNOWN_ROUTES[normalized] }
  if (PAGE_ALIASES[page]) {
    const key = PAGE_ALIASES[page]
    return { key, route: KNOWN_ROUTES[key] }
  }
  if (PAGE_ALIASES[normalized]) {
    const key = PAGE_ALIASES[normalized]
    return { key, route: KNOWN_ROUTES[key] }
  }

  const keys = Object.keys(KNOWN_ROUTES)
  const contained = keys.find((k) => normalized.includes(k) || k.includes(normalized))
  if (contained) return { key: contained, route: KNOWN_ROUTES[contained] }

  const aliasHit = Object.entries(PAGE_ALIASES).find(
    ([alias]) => normalized.includes(alias) || alias.includes(normalized),
  )
  if (aliasHit) {
    const key = aliasHit[1]
    return { key, route: KNOWN_ROUTES[key] }
  }

  return null
}

'''

OLD_DESC = '''      name: 'navigate_to',
      description: `跳转到指定页面。当用户说"去XX""跳转XX""打开XX"或需要带用户查看某页面时调用。

已知页面: ${Object.keys(KNOWN_ROUTES).join('、')}

也可传 path 直接跳转（如 /demands/xxx、/orders/xxx）`,'''

NEW_DESC = '''      name: 'navigate_to',
      description: `跳转到指定页面。当用户说"去XX""跳转XX""打开XX"或需要带用户查看某页面时调用。

已知页面: ${Object.keys(KNOWN_ROUTES).join('、')}

规则：名称不必完全一致——工具会做别名/模糊匹配（如「页面中心」→首页、「个人中心」→个人主页）。选一个最接近的已知页立刻调用，禁止在思考里反复纠结。无法判断时用一句话问用户。
也可传 path 直接跳转（如 /demands/xxx、/orders/xxx）`,'''

OLD_HANDLER = '''    handler: async (args) => {
      const directPath = String(args.path || '').trim()
      if (directPath.startsWith('/')) {
        const title = directPath.split('/').filter(Boolean).pop() ?? '目标页'
        return ok({ path: directPath, title }, `正在前往${directPath}`)
      }
      const page = String(args.page || '').trim()
      if (!page) return fail('缺少目标', '请提供 page 或 path')
      const route = KNOWN_ROUTES[page]
      if (!route) return fail('未知页面', `未知页面"${page}"，已知页面: ${Object.keys(KNOWN_ROUTES).join('、')}`)
      return ok(route, `正在前往${route.title}`)
    },'''

NEW_HANDLER = '''    handler: async (args) => {
      const directPath = String(args.path || '').trim()
      if (directPath.startsWith('/')) {
        const title = directPath.split('/').filter(Boolean).pop() ?? '目标页'
        return ok({ path: directPath, title }, `正在前往${directPath}`)
      }
      const page = String(args.page || '').trim()
      if (!page) return fail('缺少目标', '请提供 page 或 path')
      const resolved = resolveKnownRoute(page)
      if (!resolved) {
        return fail(
          '未知页面',
          `未知页面"${page}"。可试：${Object.keys(KNOWN_ROUTES).join('、')}。若口语别名未收录，请换一个更具体的页面名。`,
        )
      }
      const { key, route } = resolved
      const note = key === page ? '' : `（已将「${page}」映射为「${key}」）`
      return ok(route, `正在前往${route.title}${note}`)
    },'''

OLD_NAV_PROMPT = '''【页面跳转】
- 用户说「去/打开/跳转 XX 页面」时，调用 navigate_to 工具；跳转前用一句话说明目的
- 查完数据后若用户需要亲自操作，可建议跳转到对应页面'''

NEW_NAV_PROMPT = '''【页面跳转】
- 用户说「去/打开/跳转 XX」时，立刻调用 navigate_to；跳转前用一句话说明目的
- 页面名不必与列表完全一致：选最接近的已知页调用即可（「页面中心/主页」→首页，「个人中心/我的」→个人主页）。工具侧会做别名匹配
- 禁止在思考中反复纠结「到底是哪一页」导致零输出；最多想一轮，然后调用工具或一句话追问
- 查完数据后若用户需要亲自操作，可建议跳转到对应页面'''


def patch_tools() -> None:
    text = TOOLS.read_text()
    marker = "function registerNavigateTool() {"
    if "function resolveKnownRoute(" not in text:
        idx = text.find(marker)
        if idx < 0:
            raise SystemExit("registerNavigateTool not found")
        text = text[:idx] + RESOLVER + text[idx:]
    if OLD_DESC not in text:
        raise SystemExit("navigate_to description block not found")
    text = text.replace(OLD_DESC, NEW_DESC, 1)
    if OLD_HANDLER not in text:
        raise SystemExit("navigate_to handler block not found")
    text = text.replace(OLD_HANDLER, NEW_HANDLER, 1)
    TOOLS.write_text(text)
    print("patched tools.ts")


def patch_executor() -> None:
    text = EXEC.read_text()
    if OLD_NAV_PROMPT not in text:
        raise SystemExit("nav prompt block not found")
    text = text.replace(OLD_NAV_PROMPT, NEW_NAV_PROMPT, 1)
    EXEC.write_text(text)
    print("patched executor.ts")


if __name__ == "__main__":
    patch_tools()
    patch_executor()
    print("OK")
