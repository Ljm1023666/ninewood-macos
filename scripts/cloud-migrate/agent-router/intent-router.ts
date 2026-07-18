import { config } from '../../config.js'
import { chatCompletion, parseJSON } from '../ai/client.js'
import {
  getCapabilityById,
  matchCapabilities,
  type Capability,
  type MatchedCapability,
} from './capability-matcher.js'
import { fidelityFor, type DataFidelityDomain } from './data-fidelity.js'

export type RouteKind = 'mechanical' | 'analytical' | 'fallback'

export interface IntentRoute {
  kind: RouteKind
  capability?: Capability
  confidence: number
  reason: string
  arguments?: Record<string, unknown>
  fidelity: DataFidelityDomain[]
}

const NO_ARG_TOOLS = new Set([
  'list_my_demands',
  'list_my_orders',
  'list_my_applications',
  'get_user_profile',
])

const REQUIRED_ARGS: Record<string, string[]> = {
  read_knowledge: ['query'],
  navigate_to: ['page'],
  search_users: ['keyword'],
  get_demand_detail: ['demandId'],
}

function executionOf(capability: Capability): 'auto_background' | 'confirm' | 'analysis' {
  if (capability.execution) return capability.execution
  if (capability.layer === 'reasoning') return 'analysis'
  if (capability.requires_confirm || capability.side_effect.startsWith('write')) {
    return 'confirm'
  }
  return 'auto_background'
}

function pickMatched(
  message: string,
  matches: MatchedCapability[],
): MatchedCapability | null {
  const analysis = matches.find(
    (match) =>
      executionOf(match.capability) === 'analysis' &&
      /分析|评估|判断|建议|下一步|怎么办|值不值得|是否合理|行情|趋势/.test(message),
  )
  if (analysis) return analysis

  if (/怎么|如何|什么是|为什么|有什么用|是什么意思/.test(message)) {
    const knowledge = matches.find((match) => match.capability.id === 'read_knowledge')
    if (knowledge) return knowledge
  }
  if (/去|打开|跳转|前往|进入|带我/.test(message)) {
    const navigation = matches.find((match) => match.capability.id === 'navigate_page')
    if (navigation) return navigation
  }
  if (/打开第一个|打开第一条|并打开|看第一个/.test(message)) {
    const composite = matches.find(
      (match) => match.capability.id === 'search_and_open_first',
    )
    if (composite) return composite
  }

  if (matches.length === 0) return null
  if (matches.length === 1) return matches[0]!
  if (matches[0]!.score > matches[1]!.score) return matches[0]!
  return null
}

function demandIdFrom(message: string, context?: Record<string, unknown>): string | null {
  const explicit = message.match(
    /(?:需求(?:ID)?|编号|#)\s*[:：#]?\s*([a-zA-Z0-9_-]{8,})/,
  )?.[1]
  if (explicit) return explicit
  const rawPath =
    typeof context?.path === 'string'
      ? context.path
      : typeof context?.route === 'string'
        ? context.route
        : ''
  return rawPath.match(/\/demands\/([a-zA-Z0-9_-]+)/)?.[1] ?? null
}

function cleanSearchKeyword(message: string, kind: 'demand' | 'user'): string {
  let value = message
    .replace(/帮我|请|麻烦|一下|看看|查一下|搜索一下|搜一下/g, '')
    .replace(/并打开(?:第一个|第一条|首个)?/g, '')
  if (kind === 'demand') {
    value = value.replace(
      /分析|评估|搜索|搜|查找|找|相关的?|需求|有没有|有哪些|有什么/g,
      '',
    )
  } else {
    value = value.replace(
      /分析|评估|比较|谁更适合|哪个更适合|选择|搜索|搜|查找|找|用户|服务者|候选人|人/g,
      '',
    )
  }
  return value.replace(/[，。！？,.!?]/g, '').trim()
}

const CITY_ALIASES = [
  '北京', '上海', '天津', '重庆', '广州', '深圳', '杭州', '南京', '苏州',
  '成都', '武汉', '西安', '长沙', '郑州', '青岛', '厦门', '福州', '济南',
  '昆明', '合肥', '南昌', '沈阳', '大连', '哈尔滨', '长春', '乌鲁木齐',
  '拉萨', '海口', '南宁', '贵阳', '太原', '石家庄', '呼和浩特', '兰州',
  '西宁', '银川',
]

function cityNameFrom(message: string): string | null {
  const alias = CITY_ALIASES.find((city) => message.includes(city))
  if (alias) return alias
  return message.match(/([\u4e00-\u9fa5]{2,6})市(?:有|的|需求|$)/)?.[1] ?? null
}

function navigationTarget(message: string): string {
  const match = message.match(
    /(?:跳转到?|打开|前往|进入|带我(?:去|到)?|去)\s*[「『“"]?(.+?)[」』”"]?(?:页面|界面)?$/,
  )
  return (match?.[1] ?? '')
    .replace(/^(?:一下|帮我|请)/, '')
    .replace(/(?:页面|界面)$/, '')
    .trim()
}

export function extractToolArguments(
  tool: string,
  message: string,
  context?: Record<string, unknown>,
): Record<string, unknown> {
  if (NO_ARG_TOOLS.has(tool)) return {}
  if (tool === 'read_knowledge') return { query: message.trim() }
  if (tool === 'navigate_to') {
    const page = navigationTarget(message)
    return page ? { page } : {}
  }
  if (tool === 'search_demands') {
    const cityName = cityNameFrom(message)
    let keywordSource = message
    if (cityName) keywordSource = keywordSource.replace(`${cityName}市`, '').replace(cityName, '')
    const keyword = cleanSearchKeyword(keywordSource, 'demand')
    return {
      ...(cityName ? { cityName } : {}),
      ...(keyword ? { keyword } : {}),
    }
  }
  if (tool === 'search_users') {
    const keyword = cleanSearchKeyword(message, 'user')
    return keyword ? { keyword } : {}
  }
  if (tool === 'get_demand_detail') {
    const demandId = demandIdFrom(message, context)
    return demandId ? { demandId } : {}
  }
  return {}
}

function missingRequired(tool: string, args: Record<string, unknown>): string[] {
  return (REQUIRED_ARGS[tool] ?? []).filter((key) => {
    const value = args[key]
    return value == null || (typeof value === 'string' && !value.trim())
  })
}

export async function fillArgumentsWithFastModel(
  tool: string,
  message: string,
  args: Record<string, unknown>,
): Promise<Record<string, unknown> | null> {
  const missing = missingRequired(tool, args)
  if (missing.length === 0) return args
  try {
    const result = await chatCompletion({
      model: config.aiFastModel,
      thinking: false,
      temperature: 0,
      maxTokens: 160,
      messages: [
        {
          role: 'system',
          content:
            `你是参数抽取器。目标工具=${tool}。缺少字段=${missing.join(',')}。` +
            '只输出一个 JSON 对象；无法确定的字段填 null。不得解释、不得猜造 ID。',
        },
        { role: 'user', content: message },
      ],
    })
    const parsed = parseJSON(result.content)
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return null
    const merged = { ...args, ...(parsed as Record<string, unknown>) }
    return missingRequired(tool, merged).length === 0 ? merged : null
  } catch (error) {
    console.warn('[intent-router] fast slot extraction failed:', (error as Error).message)
    return null
  }
}

export function routeIntent(
  message: string,
  context?: Record<string, unknown>,
): IntentRoute {
  const matches = matchCapabilities(message)
  // 容忍「搜一下上海有哪些需求」这类在动词和对象间插入条件的自然表达。
  if (
    /(?:搜|搜索|找|查).*(?:需求|单子)/.test(message) &&
    !matches.some((match) => match.capability.id === 'search_demands')
  ) {
    const capability = getCapabilityById('search_demands')
    if (capability) matches.push({ capability, score: 1 })
  }
  const selected = pickMatched(message, matches)
  if (!selected) {
    return {
      kind: 'fallback',
      confidence: 0,
      reason: matches.length > 1 ? 'ambiguous-capabilities' : 'no-capability',
      fidelity: fidelityFor(undefined, message),
    }
  }

  const capability = selected.capability
  const execution = executionOf(capability)
  const tool = capability.tool
  const args = tool ? extractToolArguments(tool, message, context) : {}
  const confidence =
    matches.length === 1 || selected.score > (matches[1]?.score ?? 0) ? 1 : 0.75

  if (execution === 'analysis') {
    return {
      kind: 'analytical',
      capability,
      confidence,
      reason: 'analysis-playbook',
      arguments: args,
      fidelity: fidelityFor(capability.id, message),
    }
  }
  if (
    execution === 'auto_background' &&
    capability.risk === 'read' &&
    (capability.side_effect === 'none' || capability.side_effect === 'navigate')
  ) {
    return {
      kind: 'mechanical',
      capability,
      confidence,
      reason: capability.composite_chain?.length ? 'mechanical-playbook' : 'mechanical-tool',
      arguments: args,
      fidelity: fidelityFor(capability.id, message),
    }
  }

  return {
    kind: 'fallback',
    capability,
    confidence,
    reason: 'write-or-unsupported',
    arguments: args,
    fidelity: fidelityFor(capability.id, message),
  }
}

