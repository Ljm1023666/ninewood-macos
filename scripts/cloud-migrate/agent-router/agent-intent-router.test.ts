import { beforeAll, describe, expect, it, vi } from 'vitest'
import {
  invalidateCapabilityCache,
  getCapabilityById,
} from '../services/agent/capability-matcher.js'
import {
  extractToolArguments,
  routeIntent,
} from '../services/agent/intent-router.js'
import {
  invalidateDataFidelityCache,
  loadDataFidelity,
} from '../services/agent/data-fidelity.js'
import {
  buildDemandDraft,
  demandDraftArguments,
} from '../services/agent/demand-draft.js'
import { enforceDemandResultConsistency } from '../services/agent/demand-result-guard.js'
import {
  guardSearchDemandArguments,
  guardToolInvocations,
} from '../services/agent/search-argument-guard.js'
import { executeCapabilityPlaybook } from '../services/agent/playbook-executor.js'
import { toolRegistry } from '../services/agent/tool-registry.js'
import { registerNinewoodTools } from '../services/agent/tools.js'

beforeAll(() => {
  invalidateCapabilityCache()
  invalidateDataFidelityCache()
  if (!toolRegistry.get('read_knowledge')) registerNinewoodTools()
})

describe('deterministic intent router', () => {
  it('routes navigation mechanically and extracts the colloquial page alias', () => {
    const route = routeIntent('帮我跳转到页面中心')
    expect(route.kind).toBe('mechanical')
    expect(route.capability?.id).toBe('navigate_page')
    expect(route.arguments).toEqual({ page: '页面中心' })
  })

  it('routes a direct list request without invoking reasoning', () => {
    const route = routeIntent('看看我的订单')
    expect(route.kind).toBe('mechanical')
    expect(route.capability?.id).toBe('list_my_orders')
  })

  it('routes a Chinese city search mechanically and extracts the city', () => {
    const route = routeIntent('帮我搜一下上海有哪些需求')
    expect(route.kind).toBe('mechanical')
    expect(route.capability?.id).toBe('search_demands')
    expect(route.arguments).toEqual({ cityName: '上海' })
  })

  it('keeps a city filter separate from a demand keyword', () => {
    expect(
      extractToolArguments(
        'search_demands',
        '帮我搜索上海的手机贴膜需求',
      ),
    ).toEqual({ cityName: '上海', keyword: '手机贴膜' })
  })

  it('does not invent filters for a vague demand search', () => {
    const route = routeIntent('帮我搜索一下需求')
    expect(route.kind).toBe('mechanical')
    expect(route.capability?.id).toBe('search_demands')
    expect(route.arguments).toEqual({})
    expect(
      guardSearchDemandArguments('帮我搜索一下需求', {
        cityName: '上海',
        category: '设计',
      }),
    ).toEqual({})
  })

  it('keeps an explicit city and removes an invented category', () => {
    expect(
      guardSearchDemandArguments('帮我搜索上海的需求', {
        cityName: '上海',
        category: '开发',
      }),
    ).toEqual({ cityName: '上海' })
  })

  it('keeps both filters when the user explicitly supplied both', () => {
    expect(
      guardSearchDemandArguments('搜索上海的开发需求', {
        cityName: '上海市',
        category: '开发',
      }),
    ).toEqual({ cityName: '上海市', category: '开发' })
  })

  it('guards model tool invocations without mutating unrelated tools', () => {
    expect(
      guardToolInvocations(
        [
          {
            name: 'search_demands',
            arguments: { cityName: '上海', category: '设计' },
          },
          { name: 'navigate_to', arguments: { page: '发布需求' } },
        ],
        '搜索上海的需求',
      ),
    ).toEqual([
      { name: 'search_demands', arguments: { cityName: '上海' } },
      { name: 'navigate_to', arguments: { page: '发布需求' } },
    ])
  })

  it('drops demand rows that contradict the applied city filter', () => {
    const result = enforceDemandResultConsistency(
      { cityName: '上海' },
      {
        success: true,
        data: [
          { id: 'sh-1', cityName: '上海市', title: '上海贴膜' },
          { id: 'xa-1', cityName: '西安', title: '西安接送' },
        ],
        message: '找到 2 个需求',
      },
    )
    expect(result.data).toEqual([
      { id: 'sh-1', cityName: '上海市', title: '上海贴膜' },
    ])
    expect(result.message).toContain('剔除 1 个')
  })

  it('continues a multi-turn demand draft instead of resetting intent', () => {
    const history = [
      {
        role: 'user',
        content: '帮我发布一个需求，我想找一家手机贴膜店，预算300，我在南京',
      },
      {
        role: 'assistant',
        content: '请补充具体区域、服务时间和服务方式。',
      },
    ]
    const draft = buildDemandDraft(history, '百家湖 17点 上门服务')
    expect(draft.ready).toBe(true)
    expect(draft.cityName).toBe('南京')
    expect(draft.region).toBe('百家湖')
    expect(draft.serviceMode).toBe('上门')
    expect(demandDraftArguments(draft)).toMatchObject({
      category: '手机贴膜',
      minPrice: 300,
      cityName: '南京',
      region: '百家湖',
      serviceMode: '上门',
    })

    const route = routeIntent('百家湖 17点 上门服务', { demandDraft: draft })
    expect(route.kind).toBe('fallback')
    expect(route.capability?.id).toBe('create_demand')
    expect(route.reason).toBe('continue-demand-draft-ready')
  })

  it('lists exact missing draft fields without inventing them', () => {
    const draft = buildDemandDraft(
      [],
      '帮我发布一个手机贴膜需求，预算300，我在南京',
    )
    expect(draft.ready).toBe(false)
    expect(draft.missing).toEqual(['具体区域', '服务方式', '服务时间'])
  })

  it('routes demand analysis to the reasoning playbook', () => {
    const route = routeIntent('分析需求 #demand_12345678 的风险')
    expect(route.kind).toBe('analytical')
    expect(route.capability?.id).toBe('analyze_demand')
  })

  it('uses current-page context to extract a demand id', () => {
    expect(
      extractToolArguments('get_demand_detail', '分析这个需求', {
        path: '/demands/cmk123456789',
      }),
    ).toEqual({ demandId: 'cmk123456789' })
  })

  it('parses analysis composite chains from the capability matrix', () => {
    const capability = getCapabilityById('next_action_guidance')
    expect(capability?.execution).toBe('analysis')
    expect(capability?.composite_chain?.map((step) => step.tool)).toEqual([
      'list_my_demands',
      'list_my_orders',
      'list_my_applications',
    ])
  })

  it('executes search-and-open through the generic composite chain', async () => {
    const capability = getCapabilityById('search_and_open_first')!
    const execute = vi
      .spyOn(toolRegistry, 'execute')
      .mockResolvedValueOnce({
        success: true,
        data: [{ id: 'demand-123', title: 'PPT 设计' }],
        message: '找到 1 个相关需求',
      })
      .mockResolvedValueOnce({
        success: true,
        data: { path: '/demands/demand-123', title: '需求详情' },
        message: '正在前往需求详情',
      })

    const result = await executeCapabilityPlaybook(
      capability,
      '搜索 PPT 需求并打开第一个',
      {
        userId: 'u1',
        conversationId: 'c1',
        accessMode: 'full',
        send: () => {},
      },
    )

    expect(result.completed).toBe(true)
    expect(execute.mock.calls.map((call) => call[0])).toEqual([
      'search_demands',
      'navigate_to',
    ])
    expect(execute.mock.calls[1]?.[1]).toEqual({
      path: '/demands/demand-123',
    })
    execute.mockRestore()
  })
})

describe('data fidelity guard', () => {
  it('loads audited domains and flags provider geography as stub', () => {
    const domains = loadDataFidelity()
    expect(domains.length).toBeGreaterThanOrEqual(5)
    expect(domains.find((domain) => domain.id === 'provider_region')?.status).toBe(
      'stub',
    )
  })

  it('attaches provider-region limitations to provider analysis', () => {
    const route = routeIntent('分析服务者张三谁更适合')
    expect(route.kind).toBe('analytical')
    expect(route.fidelity.some((domain) => domain.id === 'provider_region')).toBe(
      true,
    )
  })
})
