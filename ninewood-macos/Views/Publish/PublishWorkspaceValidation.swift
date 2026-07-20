import Foundation

/// 对齐 Windows `demand-publish.ts` 校验。
struct PublishValidationIssue: Equatable, Sendable {
    let field: String
    let message: String
}

extension PublishWorkspaceFields {
    func validateForDemandPublish() -> [PublishValidationIssue] {
        var issues: [PublishValidationIssue] = []
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count < 2 { issues.append(.init(field: "title", message: "标题至少 2 个字")) }
        if serviceType == nil {
            issues.append(.init(field: "serviceType", message: "请选择线上或线下"))
        }
        let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if (desc.isEmpty ? t : desc).count < 2 {
            issues.append(.init(field: "description", message: "描述至少 2 个字"))
        }
        if budget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(field: "budget", message: "请填写预算"))
        }
        if category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(field: "category", message: "请填写分类"))
        }
        if serviceType == "OFFLINE", regionId == nil {
            issues.append(.init(field: "regionId", message: "线下服务请选择地区"))
        }
        return issues
    }

    func validateForServicePublish() -> [PublishValidationIssue] {
        var issues: [PublishValidationIssue] = []
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(field: "title", message: "请填写服务标题"))
        }
        if description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(field: "description", message: "请填写服务说明"))
        }
        if category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(field: "category", message: "请填写服务类别"))
        }
        return issues
    }

    var resolvedExpectedOutcome: String {
        let trimmed = expectedOutcome.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return String(trimmed.prefix(500)) }
        let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !desc.isEmpty { return String(desc.prefix(500)) }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return String(t.prefix(500)) }
        return "按约定交付"
    }

    /// 匹配路径候选（对齐 Windows derivePathsFromWorkspaceFields 简化版，带类型前缀）。
    var derivedPaths: [String] {
        var paths: [String] = []
        func push(_ raw: String) {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, !paths.contains(t) else { return }
            paths.append(t)
        }
        if !category.isEmpty { push("cat:\(category)") }
        for label in scopeLabels {
            push(label.contains(":") ? label : "tag:\(label)")
        }
        for key in suggestedKeywords.prefix(3) {
            push("kw:\(key)")
        }
        if serviceType == "ONLINE" { push("attr:online") }
        if serviceType == "OFFLINE" { push("attr:offline") }
        if let regionId { push("rgn:\(regionId)") }
        return Array(paths.prefix(12))
    }
}

/// 对齐 Windows missingQueue / answered / resolved 状态机。
struct PublishMissingQueueState: Equatable, Sendable, Codable {
    var missingQueue: [String] = []
    var answeredQueue: [String] = []
    var resolvedQueue: [String] = []
    var missingAnswers: [String: String] = [:]

    mutating func toggle(_ item: String) {
        if let idx = missingQueue.firstIndex(of: item) {
            missingQueue.remove(at: idx)
            missingAnswers.removeValue(forKey: item)
            return
        }
        if !answeredQueue.contains(item), !resolvedQueue.contains(item) {
            missingQueue.append(item)
        } else {
            // 允许从 answered/resolved 重新加入
            answeredQueue.removeAll { $0 == item }
            resolvedQueue.removeAll { $0 == item }
            missingQueue.append(item)
        }
    }

    /// 记录对队首问题的回答；返回是否全部答完。
    mutating func recordAnswerAndAdvance(_ answer: String) -> Bool {
        guard let current = missingQueue.first else { return true }
        missingAnswers[current] = answer
        missingQueue.removeFirst()
        answeredQueue.append(current)
        return missingQueue.isEmpty
    }

    mutating func resolveAllAnswered() {
        resolvedQueue.append(contentsOf: answeredQueue)
        answeredQueue = []
    }

    var currentPrompt: String? {
        guard let q = missingQueue.first else { return nil }
        return "请回答：\(q)（还可再答 \(missingQueue.count - 1) 项）"
    }
}
