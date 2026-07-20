export interface DemandDraft {
  active: boolean
  title?: string
  description?: string
  category?: string
  minPrice?: number
  cityName?: string
  region?: string
  serviceMode?: '线上' | '线下'
  scheduledAt?: string
  missing: string[]
  ready: boolean
}

type HistoryMessage = {
  role?: string
  content?: string | null
}

const CITIES = [
  '北京', '上海', '天津', '重庆', '广州', '深圳', '杭州', '南京', '苏州',
  '成都', '武汉', '西安', '长沙', '郑州', '青岛', '厦门', '福州', '济南',
  '昆明', '合肥', '南昌', '沈阳', '大连', '哈尔滨', '长春', '海口', '南宁',
  '贵阳', '太原', '石家庄', '呼和浩特', '兰州', '西宁', '银川',
]

const CATEGORY_HINTS = [
  '手机贴膜', '家政', '维修', '设计', '摄影', '翻译', '跑腿', '咨询',
]

const EXPLICIT_SEARCH = /(?:搜索|查找|帮我查|有哪些).*(?:需求|单子)/
const EXPLICIT_EXIT = /(?:取消|不发了|停止发布)|(?:(?:打开|跳转|前往).*(?:页面|找人|发现))/

function userTurns(history: HistoryMessage[], message: string): string[] {
  const turns = history
    .filter((item) => item.role === 'user' && typeof item.content === 'string')
    .map((item) => item.content!.trim())
    .filter(Boolean)
  return [...turns, message.trim()].filter(Boolean)
}

function latestDraftTurns(turns: string[]): string[] {
  let start = -1
  for (let index = turns.length - 1; index >= 0; index -= 1) {
    if (/发布|创建|发一个?需求|帮我发/.test(turns[index]!)) {
      start = index
      break
    }
  }
  if (start < 0) return []
  const draftTurns = turns.slice(start)
  const latest = draftTurns[draftTurns.length - 1] ?? ''
  if (EXPLICIT_SEARCH.test(latest) || EXPLICIT_EXIT.test(latest)) return []
  return draftTurns
}

function firstMatch(text: string, patterns: RegExp[]): string | undefined {
  for (const pattern of patterns) {
    const value = text.match(pattern)?.[1]?.trim()
    if (value) return value
  }
  return undefined
}

export function buildDemandDraft(
  history: HistoryMessage[],
  message: string,
): DemandDraft {
  const turns = latestDraftTurns(userTurns(history, message))
  if (turns.length === 0) return { active: false, missing: [], ready: false }

  const text = turns.join('，')
  const cityName = CITIES.find((city) => text.includes(city))
  const category =
    (/修车|汽车维修/.test(text) ? '汽车服务' : undefined) ??
    CATEGORY_HINTS.find((value) => text.includes(value)) ??
    firstMatch(text, [/(?:需求类型|品类|类别)[:：]?\s*([^，。；]+)/])
  const minPriceRaw = firstMatch(text, [
    /(?:预算|最低价|价格)[:：]?\s*(?:人民币|¥|￥)?\s*(\d+(?:\.\d+)?)/,
    /(?:人民币|¥|￥)\s*(\d+(?:\.\d+)?)/,
    /^\s*(\d+(?:\.\d+)?)\s*(?:元)?\s*$/,
  ])
  const latestTurn = turns[turns.length - 1] ?? ''
  const standalonePrice = latestTurn.match(/^\s*(\d+(?:\.\d+)?)\s*(?:元)?\s*$/)?.[1]
  const minPrice = Number(minPriceRaw ?? standalonePrice) || undefined
  const region = firstMatch(text, [
    /(?:具体区域|区域|地点|地址)[:：]?\s*([^，。；]+)/,
    /(?:在|位于)\s*([^，。；]{2,12}(?:湖|区|路|街道|商圈))/,
    /([\u4e00-\u9fa5]{2,10}(?:湖|区|路|街道|商圈))/,
  ])
  const serviceMode = /线上|远程/.test(text)
    ? '线上'
    : /修车|汽车维修|上门|到店|线下/.test(text)
      ? '线下'
      : undefined
  const scheduledAt = firstMatch(text, [
    /((?:今天|明天|后天)?\s*(?:上午|下午|晚上)?\s*\d{1,2}(?::\d{2})?\s*(?:点|时|pm|PM|am|AM)?)/,
  ])
  const explicitTitle = firstMatch(text, [
    /标题[:：]\s*[「『“"]?([^」』”"，,]+)/,
  ])
  const title =
    explicitTitle ??
    (category ? `寻找${category}` : undefined)
  const description =
    category && minPrice != null
      ? `${cityName ? `${cityName}` : ''}${region ? `${region}` : ''}${category}需求，预算 ${minPrice} 元${serviceMode ? `，${serviceMode}` : ''}${scheduledAt ? `，时间 ${scheduledAt}` : ''}`
      : undefined

  const missing: string[] = []
  if (!category) missing.push('需求类型')
  if (minPrice == null) missing.push('预算')
  if (!serviceMode) missing.push('服务方式')
  if (serviceMode === '线下' && !cityName) missing.push('城市')
  if (serviceMode === '线下' && !region) missing.push('具体区域')

  return {
    active: true,
    title,
    description,
    category,
    minPrice,
    cityName,
    region,
    serviceMode,
    scheduledAt,
    missing,
    ready: missing.length === 0 && Boolean(title && description),
  }
}

export function demandDraftFollowUp(draft: DemandDraft): string {
  if (!draft.active) return ''
  const known = [
    draft.category ? `类型「${draft.category}」` : '',
    draft.minPrice != null ? `预算 ${draft.minPrice} 元` : '',
    draft.cityName ? `城市「${draft.cityName}」` : '',
  ].filter(Boolean).join('、')
  const prefix = known ? `已记录${known}。` : '好的，我来帮你起草发布需求。'
  const next = draft.missing[0]
  const question: Record<string, string> = {
    '需求类型': '请说一下具体需要什么服务？',
    '预算': '你的预算是多少元？',
    '城市': '这是线下需求，需要在哪个城市？',
    '具体区域': '具体在哪个区域或地址？',
    '服务方式': '这是线上服务，还是需要到场的线下服务？',
  }
  return `${prefix}${question[next ?? ''] ?? '请确认以上信息，我再为你生成发布草稿。'}`
}

export function demandDraftArguments(
  draft: DemandDraft,
): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries({
      title: draft.title,
      description: draft.description,
      category: draft.category,
      minPrice: draft.minPrice,
      cityName: draft.cityName,
      region: draft.region,
      serviceType: draft.serviceMode === '线下' ? 'OFFLINE' : draft.serviceMode === '线上' ? 'ONLINE' : undefined,
      scheduledAt: draft.scheduledAt,
    }).filter(([, value]) => value != null && value !== ''),
  )
}
