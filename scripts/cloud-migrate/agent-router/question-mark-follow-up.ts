const QUESTION_MARK_ONLY = /^[?？\s\.。！!]+$/

export function isQuestionMarkFollowUp(message: string): boolean {
  const t = message.trim()
  return t.length > 0 && t.length <= 8 && QUESTION_MARK_ONLY.test(t)
}

export const QUESTION_MARK_FOLLOW_UP_REPLY =
  '刚才那步已经处理过了。可以说「打开找人」「搜索上海需求」或「打开第 N 个」继续。'
