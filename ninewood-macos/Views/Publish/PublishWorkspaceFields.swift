import Foundation

/// 对齐 Windows `demand-workspace` 字段模型（需求卡 / 服务卡共用工作区）。
struct PublishWorkspaceFields: Equatable, Sendable {
    var title = ""
    var description = ""
    var serviceType: String? // ONLINE / OFFLINE
    var budget = ""
    var schedule = ""
    var category = ""
    var regionId: Int?
    var expectedOutcome = ""
    var scopeLabels: [String] = []
    var suggestedKeywords: [String] = []
    var confidence = "low"
    var taxonomyLeafId: String?
    var missingInfo: [String] = []
    var readyToPublish = false
    /// 需求专属（对齐 Windows WorkspaceFields）
    var visibilityWindow: Int = 15
    var maxApplicants: Int = 10
    var timeLimitMinutes: Int? = nil

    var hasCoreContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isDemandReady: Bool {
        hasCoreContent
            && serviceType != nil
            && !budget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (serviceType != "OFFLINE" || regionId != nil)
    }

    var isServiceReady: Bool {
        hasCoreContent && !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Windows `getConfirmedContext`：已锁定字段作为 agent 上下文前缀。
    func confirmedContext(locked: Set<String>, lockedKeywords: Set<String> = []) -> String {
        let labels: [String: String] = [
            "title": "标题",
            "description": "描述",
            "serviceType": "服务类型",
            "budget": "预算",
            "schedule": "时间",
            "category": "分类",
            "regionId": "地区",
            "expectedOutcome": "预期效果",
        ]
        var items: [String] = []
        for key in locked.sorted() {
            let label = labels[key] ?? key
            let display: String
            switch key {
            case "title": display = title
            case "description": display = description
            case "serviceType":
                display = serviceType == "ONLINE" ? "线上" : serviceType == "OFFLINE" ? "线下" : ""
            case "budget": display = budget
            case "schedule": display = schedule
            case "category": display = category
            case "regionId": display = regionId.map(String.init) ?? ""
            case "expectedOutcome": display = expectedOutcome
            default: display = ""
            }
            if !display.isEmpty {
                items.append("\(label): \(display)")
            }
        }
        if !lockedKeywords.isEmpty {
            items.append("关键词: \(lockedKeywords.sorted().joined(separator: "、"))")
        }
        guard !items.isEmpty else { return "" }
        return "[已确认] \(items.joined(separator: " | "))"
    }

    /// Windows `requirementState`：confirmed = 锁定字段值；pending = missingInfo。
    func requirementState(locked: Set<String>) -> PublishRequirementState {
        var confirmed: [String: String] = [:]
        for key in locked {
            let value: String
            switch key {
            case "title": value = title
            case "description": value = description
            case "serviceType": value = serviceType ?? ""
            case "budget": value = budget
            case "schedule": value = schedule
            case "category": value = category
            case "regionId": value = regionId.map(String.init) ?? ""
            case "expectedOutcome": value = expectedOutcome
            default: value = ""
            }
            if !value.isEmpty {
                confirmed[key] = value
            }
        }
        return PublishRequirementState(confirmed: confirmed, pending: missingInfo)
    }

    mutating func applyAgentArgs(_ args: [String: String], locked: Set<String>) {
        if !locked.contains("title"), let v = args["title"], !v.isEmpty { title = v }
        if !locked.contains("description"), let v = args["description"], !v.isEmpty { description = v }
        if !locked.contains("serviceType"), let v = args["serviceType"], !v.isEmpty { serviceType = v }
        if !locked.contains("budget"), let v = args["budget"], !v.isEmpty { budget = v }
        if !locked.contains("schedule"), let v = args["schedule"], !v.isEmpty { schedule = v }
        if !locked.contains("category"), let v = args["category"], !v.isEmpty { category = v }
        if !locked.contains("expectedOutcome"), let v = args["expectedOutcome"], !v.isEmpty {
            expectedOutcome = v
        }
        if !locked.contains("regionId"), let raw = args["regionId"], let id = Int(raw) {
            regionId = id
        }
        readyToPublish = isDemandReady || isServiceReady
    }

    mutating func applyAnalyze(_ result: PublishAnalyzeResult, locked: Set<String>) {
        if !locked.contains("title"), let v = result.title, !v.isEmpty { title = v }
        if !locked.contains("description") {
            if let v = result.summary, !v.isEmpty { description = v }
        }
        if !locked.contains("expectedOutcome"), let v = result.expectedOutcome, !v.isEmpty {
            expectedOutcome = v
        }
        if !locked.contains("serviceType"), let v = result.serviceType, !v.isEmpty {
            serviceType = v
        }
        if !locked.contains("budget"), let v = result.budget, !v.isEmpty { budget = v }
        if !locked.contains("schedule"), let v = result.schedule, !v.isEmpty { schedule = v }
        if !locked.contains("category"), let v = result.category, !v.isEmpty { category = v }
        if !locked.contains("regionId"), let id = result.regionId { regionId = id }
        if let conf = result.confidence { confidence = conf }
        let scopes = result.effectiveScopeLabels
        if !scopes.isEmpty { scopeLabels = scopes }
        if let keys = result.suggestedKeywords, !keys.isEmpty { suggestedKeywords = keys }
        if let leaf = result.taxonomyLeafId, !leaf.isEmpty { taxonomyLeafId = leaf }
        if let missing = result.missingInfo { missingInfo = missing }
        if let ready = result.readyToPublish {
            readyToPublish = ready
        } else {
            readyToPublish = isDemandReady || isServiceReady
        }
    }

    /// 结构化 AI 暂不可用时的本地草稿兜底。
    /// 只提取用户原文中明确出现的信息，不臆造城市或价格；后续 AI result
    /// 仍可通过 `applyAnalyze` 覆盖这些未锁定字段。
    mutating func seedFromUserText(
        _ rawText: String,
        serviceCard: Bool,
        regions: [RegionDTO],
        locked: Set<String>
    ) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if !locked.contains("description"), description.isEmpty {
            description = text
        }

        if !locked.contains("title"), title.isEmpty {
            let cleaned = text
                .replacingOccurrences(of: #"^(测试需求|测试服务|需求|服务)[：:]\s*"#, with: "", options: .regularExpression)
            let firstClause = cleaned
                .split(whereSeparator: { "，。；\n".contains($0) })
                .first
                .map(String.init) ?? cleaned
            title = String(firstClause.prefix(36))
        }

        if !locked.contains("serviceType"), serviceType == nil {
            if text.contains("线下") {
                serviceType = "OFFLINE"
            } else if text.contains("线上") {
                serviceType = "ONLINE"
            }
        }

        if !locked.contains("budget"), budget.isEmpty {
            let patterns = [
                #"(?:预算|报价|价格)[^\d]{0,6}(\d+(?:\.\d+)?)(?:\s*(?:到|至|[-~—])\s*(\d+(?:\.\d+)?))?"#,
                #"(\d+(?:\.\d+)?)\s*(?:到|至|[-~—])\s*(\d+(?:\.\d+)?)\s*元"#,
            ]
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(
                        in: text,
                        range: NSRange(text.startIndex..., in: text)
                      )
                else { continue }
                var values: [String] = []
                for index in 1 ..< match.numberOfRanges {
                    let range = match.range(at: index)
                    if range.location != NSNotFound, let swiftRange = Range(range, in: text) {
                        values.append(String(text[swiftRange]))
                    }
                }
                if !values.isEmpty {
                    budget = values.joined(separator: "-")
                    break
                }
            }
        }

        if !locked.contains("regionId"), regionId == nil {
            regionId = regions.first(where: { region in
                guard let name = region.name else { return false }
                let shortName = name
                    .replacingOccurrences(of: "特别行政区", with: "")
                    .replacingOccurrences(of: "自治区", with: "")
                    .replacingOccurrences(of: "省", with: "")
                    .replacingOccurrences(of: "市", with: "")
                return (!shortName.isEmpty && text.contains(shortName)) || text.contains(name)
            })?.id
        }

        if !locked.contains("category"), category.isEmpty {
            let categoryKeywords: [(String, [String])] = [
                ("家政/维修", ["维修", "修理", "保养", "安装", "修车"]),
                ("设计", ["设计", "海报", "视觉", "UI"]),
                ("开发", ["开发", "编程", "网站", "小程序"]),
                ("教育/辅导", ["辅导", "教学", "培训", "家教"]),
                ("跑腿/配送", ["跑腿", "代取", "代送", "配送"]),
                ("日常服务", ["服务"]),
            ]
            category = categoryKeywords.first(where: { _, keywords in
                keywords.contains(where: text.contains)
            })?.0 ?? ""
        }

        if !serviceCard, !locked.contains("expectedOutcome"), expectedOutcome.isEmpty {
            let outcomePrefixes = ["希望", "期望", "要求"]
            if let prefix = outcomePrefixes.first(where: text.contains),
               let range = text.range(of: prefix) {
                let suffix = text[range.lowerBound...]
                    .split(whereSeparator: { "。；\n".contains($0) })
                    .first
                    .map(String.init) ?? ""
                expectedOutcome = String(suffix.prefix(120))
            }
            if expectedOutcome.isEmpty {
                expectedOutcome = String(text.prefix(120))
            }
        }

        confidence = "medium"
        readyToPublish = serviceCard ? isServiceReady : isDemandReady
    }

    mutating func applyHandoff(_ handoff: PublishDraftHandoff) {
        if title.isEmpty { title = handoff.title }
        if description.isEmpty {
            description = handoff.description.isEmpty ? handoff.expectedOutcome : handoff.description
        }
        if expectedOutcome.isEmpty { expectedOutcome = handoff.expectedOutcome }
        if category.isEmpty { category = handoff.category }
        if budget.isEmpty {
            budget = [handoff.budgetMin, handoff.budgetMax].filter { !$0.isEmpty }.joined(separator: "-")
        }
        if serviceType == nil, !handoff.serviceType.isEmpty {
            serviceType = handoff.serviceType
        }
        if schedule.isEmpty { schedule = handoff.deliveryMode }
    }
}

struct PublishWorkspaceChatMessage: Identifiable, Equatable {
    let id: String
    var role: String // user | assistant
    var content: String
    var isStreaming: Bool = false
    var toolArgs: [String: String]? = nil
    /// Windows Think 多轮：回传给 `agent-demand-stream` 的 `reasoning_content`
    var reasoningContent: String? = nil
}
