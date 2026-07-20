import { describe, expect, it } from 'vitest'
import {
  guardSearchDemandArguments,
  guardToolInvocations,
} from '../services/agent/search-argument-guard.js'

describe('search argument guard', () => {
  it('drops invented filters for a vague demand search', () => {
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
})
