/**
 * Cap numbered list narration for SSE display. Full data[] stays intact for working-set.
 */
export function capNumberedListNarration(message: string, maxItems = 5): string {
  const lines = message.split('\n')
  if (lines.length <= maxItems + 1) return message

  const header = lines[0] ?? ''
  const numbered = lines.filter((line) => /^\d+\.\s/.test(line))
  if (numbered.length <= maxItems) return message

  const kept = numbered.slice(0, maxItems)
  const omitted = numbered.length - maxItems
  return `${header}\n${kept.join('\n')}\n…还有 ${omitted} 条未展示`
}

/** SSE tool_result payload: keep first N rows only to avoid multi-KB streams. */
export function capListDataForSse(data: unknown, maxItems = 5): unknown {
  if (!Array.isArray(data)) return data
  if (data.length <= maxItems) return data
  return data.slice(0, maxItems)
}

export function isListNarrationComplete(message: string): boolean {
  return /^\d+\.\s/m.test(message) || message.includes('没有找到') || message.includes('未指定城市')
}
