import { describe, expect, it } from 'vitest'
import { buildDemandDraft, demandDraftFollowUp } from '../services/agent/demand-draft.js'

describe('demand draft multi-turn guard', () => {
  it('keeps publish intent and treats a standalone number as budget', () => {
    const history = [
      { role: 'user', content: '帮我发布一个需求' },
      { role: 'assistant', content: '你准备叫什么内容的需求？' },
      { role: 'user', content: '修车' },
      { role: 'assistant', content: '请补充分类' },
      { role: 'user', content: '我要找人修车' },
      { role: 'assistant', content: '请补充预算' },
    ]
    const draft = buildDemandDraft(history, '300')
    expect(draft.active).toBe(true)
    expect(draft.category).toBe('汽车服务')
    expect(draft.minPrice).toBe(300)
    expect(draft.serviceMode).toBe('线下')
    expect(demandDraftFollowUp(draft)).toContain('需要在哪个城市')
  })

  it('collects the Windows demand-card minimum contract in order', () => {
    const first = buildDemandDraft([], '帮我发布一个需求')
    expect(demandDraftFollowUp(first)).toContain('具体需要什么服务')

    const second = buildDemandDraft(
      [{ role: 'user', content: '帮我发布一个需求' }],
      '修车',
    )
    expect(demandDraftFollowUp(second)).toContain('预算是多少元')
  })

  it('allows an explicit switch to searching demands', () => {
    const draft = buildDemandDraft(
      [{ role: 'user', content: '帮我发布一个需求' }],
      '改为搜索上海的需求',
    )
    expect(draft.active).toBe(false)
  })
})
