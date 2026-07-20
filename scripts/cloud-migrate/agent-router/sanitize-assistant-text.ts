/**
 * Strip model-leaked tool markup from visible assistant text.
 * Work 3B sometimes echoes <tool_call> JSON into the chat bubble.
 */
const TOOL_CALL_BLOCK =
  /<tool_call\b[^>]*>[\s\S]*?<\/tool_call>|<tool_calls\b[^>]*>[\s\S]*?<\/tool_calls>/gi
const TOOL_CALL_TAG = /<\/?tool_calls?>/gi
const TOOL_JSON_BLOB =
  /\{\s*"name"\s*:\s*"[^"]+"\s*,\s*"data"\s*:\s*\{[\s\S]*?\}\s*\}/g

export function sanitizeAssistantText(raw: string): string {
  if (!raw) return raw
  let text = raw
  text = text.replace(TOOL_CALL_BLOCK, '')
  text = text.replace(TOOL_CALL_TAG, '')
  text = text.replace(TOOL_JSON_BLOB, '')
  // Small tool models occasionally leak the tail of an internal status token
  // after an otherwise complete tool narration (for example `DING)。`).
  text = text.replace(/(?:PENDING|DING)\s*[\uff09)]?[。.]?\s*$/gi, '')
  text = text.replace(/已打开([^。\n]{0,40})页面。?\s*当前在[：:][^\n]*/g, '已打开$1。')
  text = text.replace(/当前在[：:]\s*/g, '')
  const lines = text.split('\n')
  const out: string[] = []
  let prev = ''
  for (const line of lines) {
    const t = line.trim()
    if (!t) {
      if (out.length && out[out.length - 1] !== '') out.push('')
      continue
    }
    if (t === prev) continue
    out.push(t)
    prev = t
  }
  return out.join('\n').replace(/\n{3,}/g, '\n\n').trim()
}

/** Streaming-safe stripper for <tool_call> spanning deltas. */
export function createToolCallStripper() {
  let buf = ''
  return {
    feed(chunk: string): string {
      buf += chunk
      if (buf.includes('<tool_call') && !buf.includes('</tool_call>')) {
        const i = buf.indexOf('<tool_call')
        const emit = sanitizeAssistantText(buf.slice(0, i))
        buf = buf.slice(i)
        return emit
      }
      const emit = sanitizeAssistantText(buf)
      buf = ''
      return emit
    },
    flush(): string {
      const rest = sanitizeAssistantText(buf)
      buf = ''
      return rest
    },
  }
}
