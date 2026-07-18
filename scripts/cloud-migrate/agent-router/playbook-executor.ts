import type { ToolResult } from './tool-registry.js'
import type { AgentAccessMode } from './access-mode.js'
import type { Capability, CompositeStep } from './capability-matcher.js'
import type { StoredToolCall } from './tool-narration.js'
import type { ExecutedTool } from './follow-up-tools.js'
import { processToolInvocations } from './tool-runner.js'
import {
  extractToolArguments,
  fillArgumentsWithFastModel,
} from './intent-router.js'

type PlaybookContext = {
  userId: string
  conversationId: string
  accessMode: AgentAccessMode
  send: (event: string, data: unknown) => void
}

export interface PlaybookResult {
  completed: boolean
  missingParameters: boolean
  storedCalls: StoredToolCall[]
  toolResults: ToolResult[]
  executed: ExecutedTool[]
  context: Record<string, unknown>
  persistedNarration: string
}

function resultContext(
  tool: string,
  result: ToolResult,
): Record<string, unknown> {
  const data = result.data
  const rows = Array.isArray(data) ? data : []
  const object =
    data && typeof data === 'object' && !Array.isArray(data)
      ? (data as Record<string, unknown>)
      : {}
  return {
    [`${tool}.success`]: result.success,
    [`${tool}.count`]: rows.length,
    [`${tool}.firstId`]:
      rows.length > 0 && typeof (rows[0] as { id?: unknown })?.id === 'string'
        ? (rows[0] as { id: string }).id
        : undefined,
    ...Object.fromEntries(
      Object.entries(object).map(([key, value]) => [`${tool}.${key}`, value]),
    ),
  }
}

function template(
  value: unknown,
  context: Record<string, unknown>,
): unknown {
  if (typeof value !== 'string') return value
  return value.replace(/\{([^}]+)\}/g, (full, key: string) => {
    const aliases: Record<string, string> = {
      firstId: 'search_demands.firstId',
      count: 'search_demands.count',
    }
    const resolved = context[key] ?? context[aliases[key] ?? '']
    return resolved == null ? full : String(resolved)
  })
}

function conditionPasses(
  condition: string | undefined,
  context: Record<string, unknown>,
): boolean {
  if (!condition) return true
  const normalized = condition.replace(/^search\.result\./, 'search_demands.')
  const comparison = normalized.match(/^([a-zA-Z0-9_.]+)\s*>\s*(\d+)$/)
  if (comparison) {
    return Number(context[comparison[1]!]) > Number(comparison[2])
  }
  return Boolean(context[normalized])
}

function stepArguments(
  step: CompositeStep,
  message: string,
  context: Record<string, unknown>,
  requestContext?: Record<string, unknown>,
): Record<string, unknown> {
  const extracted =
    step.params_from === 'user' || !step.params
      ? extractToolArguments(step.tool, message, requestContext)
      : {}
  const configured = Object.fromEntries(
    Object.entries(step.params ?? {}).map(([key, value]) => [
      key,
      template(value, context),
    ]),
  )
  return { ...extracted, ...configured }
}

function narration(calls: StoredToolCall[]): string {
  const lines = calls.flatMap((call) => call.steps).filter(Boolean)
  return [...new Set(lines)].map((line) => `> ${line}`).join('\n')
}

export async function executeCapabilityPlaybook(
  capability: Capability,
  message: string,
  ctx: PlaybookContext,
  requestContext?: Record<string, unknown>,
): Promise<PlaybookResult> {
  const steps: CompositeStep[] =
    capability.composite_chain && capability.composite_chain.length > 0
      ? capability.composite_chain
      : capability.tool
        ? [{ tool: capability.tool, params_from: 'user' }]
        : []

  const storedCalls: StoredToolCall[] = []
  const toolResults: ToolResult[] = []
  const executed: ExecutedTool[] = []
  const values: Record<string, unknown> = {}
  let missingParameters = false

  for (const step of steps) {
    if (!conditionPasses(step.when, values)) continue
    let args = stepArguments(step, message, values, requestContext)
    if (!step.params || step.params_from === 'user') {
      const completed = await fillArgumentsWithFastModel(step.tool, message, args)
      if (!completed) {
        missingParameters = true
        break
      }
      args = completed
    }

    const batch = await processToolInvocations(
      [{ name: step.tool, arguments: args }],
      ctx,
    )
    storedCalls.push(...batch.storedCalls)
    toolResults.push(...batch.toolResults)
    executed.push(...batch.executed)
    const result = batch.toolResults[0]
    if (!result) continue
    Object.assign(values, resultContext(step.tool, result))
    if (!result.success) break
  }

  return {
    completed: !missingParameters && toolResults.length > 0,
    missingParameters,
    storedCalls,
    toolResults,
    executed,
    context: values,
    persistedNarration: narration(storedCalls),
  }
}

