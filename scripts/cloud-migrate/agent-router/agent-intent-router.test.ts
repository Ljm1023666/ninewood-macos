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

