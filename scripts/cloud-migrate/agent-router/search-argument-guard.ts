type ToolInvocationLike = {
  name: string
  arguments?: Record<string, unknown>
}

function normalizedText(value: string): string {
  return value.replace(/\s+/g, '').replace(/市/g, '')
}

function explicitlyMentions(message: string, value: unknown): boolean {
  if (typeof value !== 'string') return false
  const candidate = normalizedText(value.trim())
  if (!candidate) return false
  return normalizedText(message).includes(candidate)
}

/**
 * Keep model-generated search filters only when the current user utterance
 * explicitly contains them. Search must broaden safely instead of silently
 * inventing a city or category.
 *
 * This guard intentionally does not rewrite keyword/query: those fields can
 * contain the user's remaining search phrase after deterministic extraction.
 */
export function guardSearchDemandArguments(
  message: string,
  args: Record<string, unknown>,
): Record<string, unknown> {
  const guarded = { ...args }

  if (
    Object.prototype.hasOwnProperty.call(guarded, 'cityName') &&
    !explicitlyMentions(message, guarded.cityName)
  ) {
    delete guarded.cityName
  }

  if (
    Object.prototype.hasOwnProperty.call(guarded, 'category') &&
    !explicitlyMentions(message, guarded.category)
  ) {
    delete guarded.category
  }

  return guarded
}

export function guardToolInvocations<T extends ToolInvocationLike>(
  invocations: T[],
  message: string,
): T[] {
  return invocations.map((call) =>
    call.name === 'search_demands'
      ? {
          ...call,
          arguments: guardSearchDemandArguments(message, call.arguments ?? {}),
        }
      : call,
  )
}

