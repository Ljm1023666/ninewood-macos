import { describe, expect, it } from 'vitest'
import {
  capNumberedListNarration,
  capListDataForSse,
  isListNarrationComplete,
} from '../services/agent/list-narration-cap.js'
import { isCapabilityQuery, CAPABILITY_REPLY } from '../services/agent/capability-query.js'

describe('live api quality runtime', () => {
  it('caps long numbered list narration for SSE', () => {
    const long = [
      '找到 20 个相关需求：',
      ...Array.from({ length: 20 }, (_, i) => `${i + 1}. 条目${i + 1}（企业服务）¥100起`),
    ].join('\n')
    const capped = capNumberedListNarration(long, 5)
    expect(capped).toContain('…还有 15 条未展示')
    expect(capped).not.toContain('20. 条目20')
  })

  it('detects capability queries', () => {
    expect(isCapabilityQuery('你能做什么？')).toBe(true)
    expect(isCapabilityQuery('帮我搜索需求')).toBe(false)
  })

  it('uses stable capability reply', () => {
    expect(CAPABILITY_REPLY).toContain('搜索')
  })

  it('caps list data for SSE payloads', () => {
    const rows = Array.from({ length: 20 }, (_, i) => ({ id: String(i) }))
    expect(capListDataForSse(rows, 5)).toHaveLength(5)
    expect(isListNarrationComplete('1. 一条\n2. 两条')).toBe(true)
  })
})
