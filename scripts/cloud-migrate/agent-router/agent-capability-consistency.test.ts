import { beforeAll, describe, expect, it } from 'vitest'
import {
  invalidateCapabilityCache,
  listCapabilities,
} from '../services/agent/capability-matcher.js'
import { toolRegistry } from '../services/agent/tool-registry.js'
import {
  KNOWN_ROUTES,
  registerNinewoodTools,
} from '../services/agent/tools.js'

beforeAll(() => {
  invalidateCapabilityCache()
  if (!toolRegistry.get('read_knowledge')) registerNinewoodTools()
})

describe('capability/tool/route consistency', () => {
  it('every declared tool and composite step exists in the registry', () => {
    const missing: string[] = []
    for (const capability of listCapabilities()) {
      if (capability.tool && !toolRegistry.get(capability.tool)) {
        missing.push(`${capability.id}:tool=${capability.tool}`)
      }
      for (const step of capability.composite_chain ?? []) {
        if (!toolRegistry.get(step.tool)) {
          missing.push(`${capability.id}:step=${step.tool}`)
        }
      }
    }
    expect(missing).toEqual([])
  })

  it('every static verification path points to a known route family', () => {
    const knownPaths = new Set(Object.values(KNOWN_ROUTES).map((route) => route.path))
    const dynamicFamilies = ['/demands/', '/orders/', '/profile/', '/payment/']
    const invalid: string[] = []

    for (const capability of listCapabilities()) {
      const path = capability.delivery.verification?.path
      if (!path) continue
      if (path === '{path}' && capability.side_effect === 'navigate') continue
      if (
        !knownPaths.has(path) &&
        !dynamicFamilies.some((prefix) => path.startsWith(prefix))
      ) {
        invalid.push(`${capability.id}:${path}`)
      }
    }
    expect(invalid).toEqual([])
  })

  it('all background capabilities are read-only or navigation', () => {
    const invalid = listCapabilities()
      .filter((capability) => capability.execution === 'auto_background')
      .filter(
        (capability) =>
          capability.risk !== 'read' ||
          !['none', 'navigate'].includes(capability.side_effect),
      )
      .map((capability) => capability.id)
    expect(invalid).toEqual([])
  })
})

