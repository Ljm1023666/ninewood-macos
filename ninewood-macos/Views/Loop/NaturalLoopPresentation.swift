import SwiftUI

enum NaturalLoopPresentation {
    static func stageTitle(_ stage: NaturalLoopStage, style: StageStyle = .default) -> String {
        switch (stage, style) {
        case (.triggered, .workspace): "意图进入自然回"
        case (.matching, .workspace): "正在匹配路径"
        case (.executing, .workspace): "执行中"
        case (.waitingHuman, .workspace): "等待人确认"
        case (.verifying, .workspace): "结果验证中"
        case (.succeeded, .workspace): "结果成立"
        case (.failed, .workspace): "结果未成立"
        case (.inconclusive, .workspace): "无法判断，可重试验证"
        case (.closed, .workspace): "已关闭"
        case (.triggered, _): "已触发"
        case (.matching, _): "匹配中"
        case (.executing, _): "执行中"
        case (.waitingHuman, _): "等待人工"
        case (.verifying, _): "验证中"
        case (.succeeded, _): "已完成"
        case (.failed, _): "失败"
        case (.inconclusive, _): "无法判断"
        case (.closed, _): "已关闭"
        case let (.unknown(value), _): value
        }
    }

    static func boundaryTitle(_ kind: NaturalLoopBoundaryKind) -> String {
        switch kind {
        case .human: "人回"
        case .earth: "地回"
        case .heaven: "天回"
        }
    }

    static func boundaryTint(_ kind: NaturalLoopBoundaryKind) -> Color {
        switch kind {
        case .human: AppTheme.human
        case .earth: AppTheme.secondary
        case .heaven: AppTheme.primary
        }
    }

    /// Design-preview actor labels (HUMAN / EARTH / HEAVEN).
    static func actorTitle(_ actor: LoopActor) -> String {
        switch actor {
        case .human: "HUMAN"
        case .earth: "EARTH"
        case .heaven: "HEAVEN"
        }
    }

    static func actorTint(_ actor: LoopActor) -> Color {
        switch actor {
        case .human: AppTheme.human
        case .earth: AppTheme.primary
        case .heaven: AppTheme.openStatus
        }
    }

    static func actorCaption(_ actor: LoopActor) -> String {
        switch actor {
        case .human: "输入需求"
        case .earth: "执行提取"
        case .heaven: "核验结果"
        }
    }

    static func availabilityTitle(available: Bool) -> String {
        available ? "可用" : "维护中"
    }

    static func availabilityTint(available: Bool) -> Color {
        available ? AppTheme.openStatus : AppTheme.urgent
    }

    static func designRunStatusTitle(_ status: DesignRunStatus) -> String {
        switch status {
        case .succeeded: "成功"
        case .running: "进行中"
        }
    }

    static func designRunStatusTint(_ status: DesignRunStatus) -> Color {
        switch status {
        case .succeeded: AppTheme.openStatus
        case .running: AppTheme.urgent
        }
    }

    static func designRunStatusSymbol(_ status: DesignRunStatus) -> String {
        switch status {
        case .succeeded: "checkmark.circle.fill"
        case .running: "clock.fill"
        }
    }

    static func executionSummary(_ execution: NaturalLoopExecution) -> String {
        if let text = loopValueText(execution.outcome), !text.isEmpty {
            return text
        }
        if execution.isPreview {
            return "当前仅生成预览，确认后会继续进入完整自然回。"
        }
        if execution.didRun {
            return "已经提交执行，可继续在自然回详情中查看验证和后续状态。"
        }
        return "当前没有直接执行成功，可稍后重试或改由人协作完成。"
    }

    nonisolated static func loopValueText(_ value: LoopValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case let .string(text):
            return text
        case let .number(number):
            return String(number)
        case let .bool(flag):
            return flag ? "是" : "否"
        case let .array(values):
            let text = values.compactMap(loopValueText).prefix(3).joined(separator: " · ")
            return text.isEmpty ? nil : text
        case let .object(object):
            if let summary = object["summary"].flatMap(loopValueText) { return summary }
            if let message = object["message"].flatMap(loopValueText) { return message }
            if let result = object["result"].flatMap(loopValueText) { return result }
            let text = object.prefix(3).compactMap { key, value -> String? in
                guard let body = loopValueText(value) else { return nil }
                return "\(key): \(body)"
            }.joined(separator: " · ")
            return text.isEmpty ? nil : text
        case .null:
            return nil
        }
    }

    static func displayDate(_ value: Date?) -> String? {
        guard let value else { return nil }
        return value.formatted(date: .abbreviated, time: .shortened)
    }

    static func canRetryVerification(stage: NaturalLoopStage) -> Bool {
        switch stage {
        case .failed, .inconclusive:
            return true
        case let .unknown(value):
            return ["FAILED", "ERROR", "INCONCLUSIVE"].contains(value.uppercased())
        default:
            return false
        }
    }

    enum StageStyle {
        case `default`
        case workspace
    }

    enum LoopActor {
        case human
        case earth
        case heaven
    }

    enum DesignRunStatus {
        case succeeded
        case running
    }
}
