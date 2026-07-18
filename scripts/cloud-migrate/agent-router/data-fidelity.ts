import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

export type FidelityStatus = 'real' | 'partial' | 'stub'

export interface DataFidelityDomain {
  id: string
  status: FidelityStatus
  keywords: string[]
  appliesTo: string[]
  evidence: string
  assistantPolicy: string
}

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const FIDELITY_FILE = path.resolve(
  __dirname,
  '../../../ai-knowledge/04-data-fidelity.yaml',
)

let cache: DataFidelityDomain[] | null = null

function inlineArray(raw: string): string[] {
  const match = raw.match(/\[(.*)\]/)
  if (!match) return []
  return match[1]!
    .split(',')
    .map((value) => value.trim().replace(/^["']|["']$/g, ''))
    .filter(Boolean)
}

function unquote(raw: string): string {
  return raw.trim().replace(/^["']|["']$/g, '')
}

export function loadDataFidelity(): DataFidelityDomain[] {
  if (cache) return cache
  if (!fs.existsSync(FIDELITY_FILE)) {
    console.warn('[data-fidelity] file not found:', FIDELITY_FILE)
    cache = []
    return cache
  }

  const rows: DataFidelityDomain[] = []
  let current: DataFidelityDomain | null = null
  for (const rawLine of fs.readFileSync(FIDELITY_FILE, 'utf8').split(/\r?\n/)) {
    const line = rawLine.trim()
    if (!line || line.startsWith('#')) continue
    const id = line.match(/^-\s+id:\s*(.+)$/)?.[1]
    if (id) {
      if (current) rows.push(current)
      current = {
        id: unquote(id),
        status: 'partial',
        keywords: [],
        appliesTo: [],
        evidence: '',
        assistantPolicy: '',
      }
      continue
    }
    if (!current) continue
    const pair = line.match(/^([a-zA-Z_]+):\s*(.*)$/)
    if (!pair) continue
    const [, key, value] = pair
    if (key === 'status' && ['real', 'partial', 'stub'].includes(value)) {
      current.status = value as FidelityStatus
    } else if (key === 'keywords') {
      current.keywords = inlineArray(value)
    } else if (key === 'applies_to') {
      current.appliesTo = inlineArray(value)
    } else if (key === 'evidence') {
      current.evidence = unquote(value)
    } else if (key === 'assistant_policy') {
      current.assistantPolicy = unquote(value)
    }
  }
  if (current) rows.push(current)
  cache = rows
  return rows
}

export function invalidateDataFidelityCache(): void {
  cache = null
}

export function fidelityFor(
  capabilityId: string | undefined,
  utterance: string,
): DataFidelityDomain[] {
  const compact = utterance.replace(/\s+/g, '').toLowerCase()
  return loadDataFidelity().filter((domain) => {
    if (capabilityId && domain.appliesTo.includes(capabilityId)) return true
    return domain.keywords.some((keyword) =>
      compact.includes(keyword.replace(/\s+/g, '').toLowerCase()),
    )
  })
}

export function buildFidelityPrompt(
  capabilityId: string | undefined,
  utterance: string,
): string {
  const guarded = fidelityFor(capabilityId, utterance).filter(
    (domain) => domain.status !== 'real',
  )
  if (guarded.length === 0) return ''
  const lines = guarded.map(
    (domain) =>
      `- ${domain.id} [${domain.status}]：${domain.assistantPolicy} 依据：${domain.evidence}`,
  )
  return `\n\n【数据真实性约束】\n${lines.join('\n')}\n不得把 partial/stub 数据表述为完整、确定的事实。`
}

