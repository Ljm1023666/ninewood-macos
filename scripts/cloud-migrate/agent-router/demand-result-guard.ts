type ToolResultLike = {
  success: boolean
  data?: unknown
  message?: string
}

function locationValues(row: Record<string, unknown>): string[] {
  const region =
    row.region && typeof row.region === 'object'
      ? (row.region as Record<string, unknown>)
      : {}
  return [
    row.cityName,
    row.city,
    row.cityCode,
    row.regionId,
    row.regionName,
    region.id,
    region.name,
    region.cityName,
  ]
    .filter((value): value is string => typeof value === 'string')
    .map((value) => value.replace(/市$/, '').trim())
    .filter(Boolean)
}

export function demandResultMatchesFilters(
  row: Record<string, unknown>,
  args: Record<string, unknown>,
): boolean {
  const cityName =
    typeof args.cityName === 'string'
      ? args.cityName.replace(/市$/, '').trim()
      : ''
  const cityCode = typeof args.cityCode === 'string' ? args.cityCode.trim() : ''
  if (!cityName && !cityCode) return true
  const values = locationValues(row)
  if (values.length === 0) return false
  return values.some(
    (value) =>
      (cityName && (value === cityName || value.includes(cityName))) ||
      (cityCode && value === cityCode),
  )
}

export function enforceDemandResultConsistency(
  args: Record<string, unknown>,
  result: ToolResultLike,
): ToolResultLike {
  if (!result.success || !Array.isArray(result.data)) return result
  if (!args.cityName && !args.cityCode) return result
  const before = result.data.length
  const rows = result.data.filter(
    (item): item is Record<string, unknown> =>
      Boolean(item) &&
      typeof item === 'object' &&
      demandResultMatchesFilters(item as Record<string, unknown>, args),
  )
  const dropped = before - rows.length
  return {
    ...result,
    data: rows,
    message:
      dropped > 0
        ? `找到 ${rows.length} 个符合地域条件的需求（已剔除 ${dropped} 个地域不一致结果）`
        : result.message,
  }
}
