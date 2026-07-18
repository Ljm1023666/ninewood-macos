#!/usr/bin/env python3
"""Apply the Ninewood deterministic agent-router refactor on the server."""
from pathlib import Path
import re
import shutil
from datetime import datetime

ROOT = Path("/opt/ninewood/server")
STAMP = datetime.now().strftime("%Y%m%d-%H%M%S")


def backup(path: Path) -> None:
    backup_path = path.with_suffix(path.suffix + f".bak-{STAMP}")
    if not backup_path.exists():
        shutil.copy2(path, backup_path)


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        if new in text:
            print(f"already patched: {path.name}")
            return
        raise RuntimeError(f"pattern not found in {path}: {old[:80]!r}")
    backup(path)
    path.write_text(text.replace(old, new, 1))
    print(f"patched: {path}")


def patch_config() -> None:
    path = ROOT / "src/config.ts"
    replace_once(
        path,
        "  byokRequired: process.env.AI_BYOK_REQUIRED === 'true',\n",
        """  byokRequired: process.env.AI_BYOK_REQUIRED === 'true',

  // 确定性 Agent 路由；设 AGENT_ROUTER_ENABLED=false 可一键回退到纯 LLM 路由
  agentRouter: {
    enabled: process.env.AGENT_ROUTER_ENABLED !== 'false',
  },
""",
    )


def patch_matcher() -> None:
    path = ROOT / "src/services/agent/capability-matcher.ts"
    text = path.read_text()
    backup(path)
    text = text.replace(
        """function signalMatches(signal: string, utterance: string): boolean {
  const s = normalize(signal);
  const u = normalize(utterance);
  if (!s) return false;
  return u.includes(s);
}""",
        """function signalMatches(signal: string, utterance: string): boolean {
  const s = normalize(signal);
  const u = normalize(utterance);
  if (!s) return false;
  // intent_signals 中的 .* 是有序通配符，不应被当成普通文本。
  if (s.includes('.*')) {
    let cursor = 0
    for (const part of s.split('.*').filter(Boolean)) {
      const index = u.indexOf(part, cursor)
      if (index < 0) return false
      cursor = index + part.length
    }
    return true
  }
  return u.includes(s);
}""",
    )

    text = text.replace(
        "export type RiskLevel = 'read' | 'low' | 'medium' | 'high' | 'forbidden';\n",
        """export type RiskLevel = 'read' | 'low' | 'medium' | 'high' | 'forbidden';
export type ExecutionMode = 'auto_background' | 'confirm' | 'analysis';

export interface CompositeStep {
  tool: string;
  params_from?: 'user';
  params?: Record<string, unknown>;
  when?: string;
}
""",
    )
    text = text.replace(
        "  plan_template?: string | null;\n  composite_chain?: unknown;\n",
        """  plan_template?: string | null;
  execution?: ExecutionMode;
  param_slots?: string[];
  composite_chain?: CompositeStep[];
  analysis_prompt?: string;
  allowed_tools?: string[];
  data_domains?: string[];
""",
    )
    text = text.replace(
        "  else if (key === 'plan_template') c.plan_template = value === 'null' ? null : value;\n",
        """  else if (key === 'plan_template') c.plan_template = value === 'null' ? null : value;
  else if (key === 'execution') c.execution = value as ExecutionMode;
  else if (key === 'analysis_prompt') c.analysis_prompt = value;
""",
    )
    text = text.replace(
        "(arrayKey === 'intent_signals' || arrayKey === 'rule_ids')",
        "(arrayKey === 'intent_signals' || arrayKey === 'rule_ids' || arrayKey === 'param_slots' || arrayKey === 'allowed_tools' || arrayKey === 'data_domains')",
    )
    text = text.replace(
        "(key === 'intent_signals' || key === 'rule_ids')",
        "(key === 'intent_signals' || key === 'rule_ids' || key === 'param_slots' || key === 'allowed_tools' || key === 'data_domains')",
    )

    marker = "\nfunction loadParsed(): ParsedYaml {\n"
    extension = r'''
/** 补充解析 capability 的嵌套扩展字段（composite_chain / 参数槽 / 分析配置）。 */
function hydrateCapabilityExtensions(raw: string, parsed: ParsedYaml): void {
  const byId = new Map(parsed.capabilities.map((cap) => [cap.id, cap]))
  const lines = raw.split(/\r?\n/)
  let current: Capability | null = null
  let inComposite = false
  let currentStep: CompositeStep | null = null
  let inParams = false
  let paramsIndent = -1

  const parseValue = (value: string): unknown => {
    const unquoted = value.trim().replace(/^["']|["']$/g, '')
    if (unquoted === 'true') return true
    if (unquoted === 'false') return false
    if (unquoted === 'null') return null
    if (/^-?\d+(?:\.\d+)?$/.test(unquoted)) return Number(unquoted)
    return unquoted
  }
  const parseInline = (value: string): string[] => {
    const match = value.match(/\[(.*)\]/)
    if (!match) return []
    return match[1]!.split(',').map((v) => String(parseValue(v))).filter(Boolean)
  }

  for (const rawLine of lines) {
    const indent = rawLine.match(/^(\s*)/)?.[1].length ?? 0
    const line = rawLine.trim()
    if (!line || line.startsWith('#')) continue

    const capId = line.match(/^-\s+id:\s*(.+)$/)?.[1]
    if (capId && indent <= 2) {
      current = byId.get(capId.replace(/^["']|["']$/g, '')) ?? null
      inComposite = false
      currentStep = null
      inParams = false
      continue
    }
    if (!current) continue

    const scalar = line.match(/^(execution|analysis_prompt):\s*(.+)$/)
    if (scalar && indent === 4) {
      if (scalar[1] === 'execution') current.execution = parseValue(scalar[2]!) as ExecutionMode
      else current.analysis_prompt = String(parseValue(scalar[2]!))
      continue
    }
    const array = line.match(/^(param_slots|allowed_tools|data_domains):\s*(\[.*\])$/)
    if (array && indent === 4) {
      const values = parseInline(array[2]!)
      if (array[1] === 'param_slots') current.param_slots = values
      else if (array[1] === 'allowed_tools') current.allowed_tools = values
      else current.data_domains = values
      continue
    }
    if (line === 'composite_chain:' && indent === 4) {
      current.composite_chain = []
      inComposite = true
      currentStep = null
      inParams = false
      continue
    }
    if (!inComposite) continue
    if (indent <= 4) {
      inComposite = false
      currentStep = null
      inParams = false
      continue
    }
    const stepTool = line.match(/^-\s+tool:\s*(.+)$/)?.[1]
    if (stepTool) {
      currentStep = { tool: String(parseValue(stepTool)) }
      current.composite_chain!.push(currentStep)
      inParams = false
      continue
    }
    if (!currentStep) continue
    const paramsFrom = line.match(/^params_from:\s*(.+)$/)?.[1]
    if (paramsFrom) {
      currentStep.params_from = String(parseValue(paramsFrom)) === 'user' ? 'user' : undefined
      continue
    }
    const when = line.match(/^when:\s*(.+)$/)?.[1]
    if (when) {
      currentStep.when = String(parseValue(when))
      inParams = false
      continue
    }
    if (line === 'params:') {
      currentStep.params = {}
      inParams = true
      paramsIndent = indent
      continue
    }
    if (inParams && indent > paramsIndent) {
      const pair = line.match(/^([a-zA-Z_]+):\s*(.+)$/)
      if (pair) currentStep.params![pair[1]!] = parseValue(pair[2]!)
    }
  }
}
'''
    if "function hydrateCapabilityExtensions" not in text:
        text = text.replace(marker, extension + marker)

    text = text.replace(
        "    cache = parseCapabilitiesYaml(raw);\n",
        "    cache = parseCapabilitiesYaml(raw);\n    hydrateCapabilityExtensions(raw, cache);\n",
    )
    path.write_text(text)
    print(f"patched: {path}")


def patch_tools() -> None:
    path = ROOT / "src/services/agent/tools.ts"
    text = path.read_text()
    backup(path)
    text = text.replace(
        """          cityCode: { type: 'string', description: '城市代码' },
          minPrice:""",
        """          cityCode: { type: 'string', description: '城市代码' },
          cityName: { type: 'string', description: '中文城市名，如"上海""杭州"' },
          minPrice:""",
        1,
    )
    text = text.replace(
        """    handler: async (args, _ctx) => {
      const filters = {
        keyword: (args.keyword as string) || undefined,
        category: (args.category as string) || undefined,
        serviceType: args.serviceType as 'ONLINE' | 'OFFLINE' | undefined,
        cityCode: (args.cityCode as string) || undefined,""",
        """    handler: async (args, _ctx) => {
      const cityName = String(args.cityName || '').trim().replace(/市$/, '')
      let cityCode = (args.cityCode as string) || undefined
      if (!cityCode && cityName) {
        const region = await safePrisma(() =>
          prisma.region.findFirst({
            where: {
              name: { contains: cityName },
              level: { in: [2, 3] },
            },
            orderBy: { level: 'desc' },
            select: { id: true, name: true },
          }),
        )
        if (!region) return fail('城市不存在', `没有识别到城市「${cityName}」`)
        cityCode = String(region.id)
      }
      const filters = {
        keyword: (args.keyword as string) || undefined,
        category: (args.category as string) || undefined,
        serviceType: args.serviceType as 'ONLINE' | 'OFFLINE' | undefined,
        cityCode,""",
        1,
    )
    text = text.replace(
        "const KNOWN_ROUTES: Record<string, { path: string; title: string }> = {",
        "export const KNOWN_ROUTES: Record<string, { path: string; title: string }> = {",
    )
    text = text.replace(
        "function resolveKnownRoute(rawPage: string):",
        "export function resolveKnownRoute(rawPage: string):",
    )

    marker = "\n// ─── 导航工具"
    market_tool = r'''
// 市场统计（只读；供分析型 playbook 后台采集）
function registerMarketTools(): void {
  toolRegistry.register({
    definition: {
      name: 'get_market_stats',
      description: '读取平台标签行情聚合数据。仅供趋势参考，覆盖范围可能不完整。',
      parameters: {
        type: 'object',
        properties: {
          tagName: { type: 'string', description: '可选：标签名称' },
          regionId: { type: 'number', description: '可选：地区 ID' },
          limit: { type: 'number', description: '返回数量，默认 20，最多 50' },
        },
      },
    },
    category: 'system',
    requiresConfirmation: false,
    handler: async (args) => {
      const tagName = String(args.tagName || '').trim() || undefined
      const regionId = typeof args.regionId === 'number' ? args.regionId : undefined
      const limit = Math.min(Math.max(Number(args.limit) || 20, 1), 50)
      const rows = await safePrisma(() =>
        prisma.tagStats.findMany({
          where: {
            ...(tagName ? { tagName } : {}),
            ...(regionId ? { regionId } : {}),
          },
          orderBy: { totalAmount: 'desc' },
          take: limit,
        }),
      )
      return ok(
        rows.map((row) => ({
          tagName: row.tagName,
          regionId: row.regionId,
          averageAmount: Number(row.avgAmount),
          sampleCount: row.totalCards,
          totalAmount: Number(row.totalAmount),
        })),
        rows.length > 0
          ? `已读取 ${rows.length} 条行情样本（统计覆盖有限）`
          : '暂无匹配的行情样本',
      )
    },
  })
}
'''
    if "function registerMarketTools" not in text:
        text = text.replace(marker, market_tool + marker)
    text = text.replace(
        "  registerKnowledgeTools();\n  registerNavigateTool();",
        "  registerKnowledgeTools();\n  registerMarketTools();\n  registerNavigateTool();",
    )
    path.write_text(text)
    print(f"patched: {path}")


def patch_narration() -> None:
    path = ROOT / "src/services/agent/tool-narration.ts"
    replace_once(
        path,
        "  read_knowledge: (a) =>\n    a.query ? `正在查阅知识库：${a.query}` : '正在查阅平台知识库',\n",
        """  read_knowledge: (a) =>
    a.query ? `正在查阅知识库：${a.query}` : '正在查阅平台知识库',
  get_market_stats: (a) =>
    a.tagName ? `正在读取「${a.tagName}」行情样本` : '正在读取市场行情样本',
""",
    )


def patch_executor() -> None:
    path = ROOT / "src/services/agent/executor.ts"
    text = path.read_text()
    backup(path)
    text = text.replace(
        "import { matchForbidden } from './capability-matcher.js';",
        """import { matchForbidden, type Capability } from './capability-matcher.js';
import { routeIntent, type IntentRoute } from './intent-router.js';
import { executeCapabilityPlaybook } from './playbook-executor.js';
import { buildFidelityPrompt } from './data-fidelity.js';""",
    )
    text = text.replace(
        "import { inferFollowUpTools, type ExecutedTool } from './follow-up-tools.js';",
        "import type { ExecutedTool } from './follow-up-tools.js';",
    )
    text = text.replace(
        "    context?: Record<string, unknown>;\n  },",
        """    context?: Record<string, unknown>;
    capability?: Capability;
    userMessage?: string;
  },""",
        1,
    )

    old_tools_prompt = re.compile(
        r"\n  if \(options\.useTools\) \{\n    prompt \+= `\n你可以调用工具来完成操作.*?\n  \}\n\n  // 注入技能提示",
        re.S,
    )
    replacement = r'''
  if (options.capability) {
    const capability = options.capability
    prompt += `\n\n【本轮已选定能力】\n- ID: ${capability.id}\n- 执行模式: ${capability.execution ?? capability.layer}\n- 你无需重新选择方案或工具；系统已处理机械步骤。`
    if (capability.analysis_prompt) {
      prompt += `\n- 分析任务: ${capability.analysis_prompt}`
    }
  }
  prompt += `

【职责边界】
- 你的核心价值是分析、判断、解释风险和给出下一步行动指南
- 页面跳转、查询、列表、固定写操作由系统工具层负责；不要在回答中反复讨论该选哪个工具
- 系统提供的数据是证据；证据不足时明确说明，不得补造事实`
  prompt += buildFidelityPrompt(options.capability?.id, options.userMessage ?? '')

  if (options.useTools) {
    prompt += `

【工具兜底】
- 只有系统未预先完成机械步骤、且确实缺少数据时才调用工具
- 只读工具可直接调用；写操作仍受访问模式与批准流程约束
- 工具失败时简短说明原因并给出可执行的修正建议`
  }

  // 注入技能提示'''
    text, count = old_tools_prompt.subn(replacement, text, count=1)
    if count != 1:
        raise RuntimeError("executor tools prompt block not found")

    # Remove the early system prompt/messages construction. It is rebuilt after routing.
    early = """  // 系统提示
  const systemPrompt = buildSystemPrompt(
    { userId, conversationId },
    { useTools, accessMode, context: params.context },
  );

  const messages = buildMessages(systemPrompt, message, history);

"""
    if early not in text:
        raise RuntimeError("early prompt block not found")
    text = text.replace(early, "", 1)

    anchor = """    await truncateTitle(conversationId, message);

    // ── 多轮 tool loop（Wave D）：最多 MAX_CHAIN_DEPTH 轮 tool_use 循环 ──
    const selectedModel = model || (thinking ? config.aiThinkModel : config.aiFastModel);
    const toolCtx = { userId, conversationId, accessMode, send };
    const allStoredCalls: StoredToolCall[] = [];
    const allExecuted: ExecutedTool[] = [];
"""
    routed = """    await truncateTitle(conversationId, message);

    const route: IntentRoute = config.agentRouter.enabled
      ? routeIntent(message, params.context)
      : { kind: 'fallback', confidence: 0, reason: 'router-disabled', fidelity: [] }
    const effectiveThinking = route.kind === 'analytical' ? true : thinking
    const selectedModel = model || (effectiveThinking ? config.aiThinkModel : config.aiFastModel)
    const toolCtx = { userId, conversationId, accessMode, send }

    // 高置信机械意图：不调用大模型，按 capability/playbook 在后台直接执行。
    if (config.agentRouter.enabled && route.kind === 'mechanical' && route.capability) {
      const fast = await executeCapabilityPlaybook(
        route.capability,
        message,
        toolCtx,
        params.context,
      )
      if (fast.completed) {
        await addMessage({
          conversationId,
          role: 'assistant',
          content: fast.persistedNarration,
          toolCalls: fast.storedCalls.map((call) => ({
            id: call.id,
            name: call.name,
            arguments: call.arguments,
            status: call.status,
            steps: call.steps,
            result: call.result,
            data: call.data,
            success: call.success,
          })),
        })
        send('done', 'ok')
        return
      }
    }

    const roundUsesTools = useTools && route.kind !== 'analytical'
    const systemPrompt = buildSystemPrompt(
      { userId, conversationId },
      {
        useTools: roundUsesTools,
        accessMode,
        context: params.context,
        capability: route.capability,
        userMessage: message,
      },
    )
    const messages = buildMessages(systemPrompt, message, history)

    // ── 多轮 tool loop（Wave D）：最多 MAX_CHAIN_DEPTH 轮 tool_use 循环 ──
    const allStoredCalls: StoredToolCall[] = [];
    const allExecuted: ExecutedTool[] = [];
    let backgroundNarration = ''

    // 分析型能力先按 playbook 静默采集真实只读数据，再交给大模型综合。
    if (route.kind === 'analytical' && route.capability) {
      const gathered = await executeCapabilityPlaybook(
        route.capability,
        message,
        toolCtx,
        params.context,
      )
      allStoredCalls.push(...gathered.storedCalls)
      allExecuted.push(...gathered.executed)
      backgroundNarration = gathered.persistedNarration
      if (gathered.toolResults.length > 0) {
        messages.push({
          role: 'system',
          content:
            '以下是系统按预设方案在后台收集的真实数据。只基于这些数据分析；不要补造：\\n' +
            JSON.stringify(
              gathered.executed.map((item) => ({
                tool: item.name,
                success: item.result.success,
                data: item.result.data,
                message: item.result.message,
              })),
            ),
        })
      }
    }
"""
    if anchor not in text:
        raise RuntimeError("executor loop anchor not found")
    text = text.replace(anchor, routed, 1)

    text = text.replace(
        "      if (!thinking && thinkStripper === null) {",
        "      if (!effectiveThinking && thinkStripper === null) {",
        1,
    )
    text = text.replace(
        "        thinking,\n        webSearch: useWebSearch,\n        useTools,",
        "        thinking: effectiveThinking,\n        webSearch: useWebSearch,\n        useTools: roundUsesTools,",
        1,
    )
    text = text.replace(
        "        model,\n        thinking,\n        send,",
        "        selectedModel,\n        effectiveThinking,\n        send,",
        1,
    )
    text = text.replace(
        "      content: lastRoundText || '',\n      thinking: lastRoundThinking || undefined,",
        """      content: [backgroundNarration, lastRoundText].filter(Boolean).join('\\n\\n'),
      thinking: lastRoundThinking || undefined,""",
        1,
    )
    legacy_follow_up = """      // 首轮意图跟进（如「搜索并打开第一个」）
      let followUpExtras: Awaited<ReturnType<typeof processToolInvocations>> | null = null;
      if (chainDepth === 0) {
        const followUps = inferFollowUpTools(message, executed);
        if (followUps.length > 0) {
          followUpExtras = await processToolInvocations(followUps, toolCtx);
        }
      }

      const combined = {
        storedCalls: [...storedCalls, ...(followUpExtras?.storedCalls ?? [])],
        toolResults: [...toolResults, ...(followUpExtras?.toolResults ?? [])],
        executed: [...executed, ...(followUpExtras?.executed ?? [])],
      };"""
    text = text.replace(
        legacy_follow_up,
        """      // 机械复合链由 capability.composite_chain 的通用执行器负责。
      const combined = { storedCalls, toolResults, executed };""",
        1,
    )
    path.write_text(text)
    print(f"patched: {path}")


def patch_yaml() -> None:
    path = ROOT / "ai-knowledge/03-agent-capabilities.yaml"
    text = path.read_text()
    backup(path)
    execution_by_id = {
        "read_knowledge": "auto_background",
        "navigate_page": "auto_background",
        "search_demands": "auto_background",
        "get_demand_detail": "auto_background",
        "search_and_open_first": "auto_background",
        "list_my_demands": "auto_background",
        "list_my_orders": "auto_background",
        "list_my_applications": "auto_background",
        "get_user_profile": "auto_background",
        "search_users": "auto_background",
        "create_demand": "confirm",
        "update_demand": "confirm",
        "withdraw_demand": "confirm",
        "apply_for_demand": "confirm",
        "accept_applicant": "confirm",
        "reject_applicant": "confirm",
        "batch_withdraw_demands": "confirm",
        "schedule_demand_digest": "auto_background",
    }
    lines = text.splitlines()
    out = []
    current_id = None
    seen_execution = False
    for line in lines:
        match = re.match(r"  - id:\s*(\S+)", line)
        if match:
            current_id = match.group(1).strip("'\"")
            seen_execution = False
        if current_id and re.match(r"    execution:", line):
            seen_execution = True
        out.append(line)
        if (
            current_id in execution_by_id
            and re.match(r"    layer:", line)
            and not seen_execution
        ):
            out.append(f"    execution: {execution_by_id[current_id]}")
            seen_execution = True
    text = "\n".join(out) + "\n"
    text = text.replace(
        "intent_signals: [搜需求, 搜索需求, 找需求, 查需求, 有没有.*需求]",
        "intent_signals: [搜需求, 搜索需求, 找需求, 查需求, 有没有.*需求, 搜.*需求, 搜索.*需求, 找.*需求, 查.*需求]",
    )

    slot_insertions = {
        "read_knowledge": "    param_slots: [query:full_utterance]\n",
        "navigate_page": "    param_slots: [page:navigation_target]\n",
        "search_demands": "    param_slots: [keyword:search_keyword]\n",
        "get_demand_detail": "    param_slots: [demandId:demand_id_or_context]\n",
        "search_users": "    param_slots: [keyword:user_keyword]\n",
    }
    for cap_id, addition in slot_insertions.items():
        pattern = rf"(  - id: {re.escape(cap_id)}\n(?:.*\n)*?    intent_signals:.*\n)"
        text, count = re.subn(pattern, rf"\1{addition}", text, count=1)
        if count != 1:
            raise RuntimeError(f"failed to add slots to {cap_id}")

    # 任务管理独立页面尚不存在，交付链接回到真实存在的 AI 助手页。
    text = text.replace("        path: /agent/tasks", "        path: /agent")

    analysis_block = r'''
  # ─── Phase 5：分析型能力（先采集真实数据，再由大模型推理）───

  - id: analyze_demand
    layer: reasoning
    execution: analysis
    tool: null
    risk: read
    side_effect: none
    intent_signals: [分析需求, 评估需求, 需求合理吗, 需求风险, 值不值得接]
    param_slots: [demandId:demand_id_or_context]
    allowed_tools: [get_demand_detail, get_market_stats]
    data_domains: [demand_region, tag_statistics]
    analysis_prompt: "从目标、预算、履约难度、风险、信息缺口和下一步行动分析该需求。"
    composite_chain:
      - tool: get_demand_detail
        params_from: user
    requires_confirm: false
    delivery:
      summary_template: "已完成需求分析"

  - id: analyze_providers
    layer: reasoning
    execution: analysis
    tool: null
    risk: read
    side_effect: none
    intent_signals: [分析服务者, 评估服务者, 比较服务者, 谁更适合, 选择服务者]
    param_slots: [keyword:user_keyword]
    allowed_tools: [search_users]
    data_domains: [provider_region]
    analysis_prompt: "比较候选人的认证、经验、完成量与信息缺口；不得把地域匹配当作可靠事实。"
    composite_chain:
      - tool: search_users
        params_from: user
    requires_confirm: false
    delivery:
      summary_template: "已完成服务者分析"

  - id: analyze_market
    layer: reasoning
    execution: analysis
    tool: null
    risk: read
    side_effect: none
    intent_signals: [分析行情, 市场行情, 市场趋势, 价格趋势, 行情怎么样]
    allowed_tools: [get_market_stats]
    data_domains: [tag_statistics, demand_region, provider_region]
    analysis_prompt: "基于有限样本解释价格与供需趋势，明确样本覆盖和不能下定论的部分。"
    composite_chain:
      - tool: get_market_stats
        params_from: user
    requires_confirm: false
    delivery:
      summary_template: "已完成行情分析"

  - id: next_action_guidance
    layer: reasoning
    execution: analysis
    tool: null
    risk: read
    side_effect: none
    intent_signals: [下一步, 接下来怎么办, 我该怎么办, 行动建议, 帮我判断下一步]
    allowed_tools: [list_my_demands, list_my_orders, list_my_applications]
    analysis_prompt: "结合用户当前需求、订单和申请状态，给出按优先级排序的下一步行动；需要机械操作时明确可由系统代办。"
    composite_chain:
      - tool: list_my_demands
        params_from: user
      - tool: list_my_orders
        params_from: user
      - tool: list_my_applications
        params_from: user
    requires_confirm: false
    delivery:
      summary_template: "已生成下一步行动指南"

'''
    marker = "# ── 交付模板片段"
    if "  - id: analyze_demand\n" not in text:
        text = text.replace(marker, analysis_block + marker)
    path.write_text(text)
    print(f"patched: {path}")


def patch_existing_tests() -> None:
    path = ROOT / "src/__tests__/agent-knowledge.test.ts"
    text = path.read_text()
    backup(path)
    text = text.replace(
        "loads all 4 yaml files from server/ai-knowledge",
        "loads all yaml files from server/ai-knowledge",
    )
    if "'04-data-fidelity.yaml'" not in text:
        text = text.replace(
            "      '03-agent-capabilities.yaml',",
            "      '03-agent-capabilities.yaml',\n      '04-data-fidelity.yaml',",
        )
    path.write_text(text)
    print(f"patched: {path}")


def main() -> None:
    patch_config()
    patch_matcher()
    patch_tools()
    patch_narration()
    patch_yaml()
    patch_executor()
    patch_existing_tests()
    print("agent router patch applied")


if __name__ == "__main__":
    main()

