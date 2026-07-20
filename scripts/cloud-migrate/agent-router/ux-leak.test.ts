import { describe, expect, it } from 'vitest'
import { sanitizeAssistantText } from '../services/agent/sanitize-assistant-text.js'
import {
  extractNavigateTarget,
  resolveNavigateTarget,
} from '../services/agent/navigate-intent.js'
import { isQuestionMarkFollowUp } from '../services/agent/question-mark-follow-up.js'

describe('ux leak fixes', () => {
  it('strips leaked tool_call markup from assistant text', () => {
    const raw =
      '已打开找人页面。当前在: <tool_call>\n{"name": "path", "data": {"page": "/search", "title": "找人"}}\n</tool_call>\n已打开找人。'
    const clean = sanitizeAssistantText(raw)
    expect(clean).not.toContain('<tool_call>')
    expect(clean).not.toContain('"name"')
    expect(clean).toContain('已打开')
  })

  it('resolves navigate intents including typo 发人', () => {
    expect(extractNavigateTarget('打开发人页面')).toBeTruthy()
    expect(resolveNavigateTarget('发人')?.path).toBe('/search')
    expect(resolveNavigateTarget('找人')?.title).toBe('找人')
    expect(extractNavigateTarget('帮我跳转到找人页面')).toBeTruthy()
  })

  it('treats ?? as question-mark follow-up', () => {
    expect(isQuestionMarkFollowUp('?')).toBe(true)
    expect(isQuestionMarkFollowUp('??')).toBe(true)
  })
})
