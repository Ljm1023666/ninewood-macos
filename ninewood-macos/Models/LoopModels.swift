import Foundation

/// 回的类型由当前边界最外层的起点与终点决定，与生命周期无关。
enum LoopKind: String, Codable, CaseIterable, Hashable, Sendable {
    case human = "HUMAN"
    case earth = "EARTH"
    case heaven = "HEAVEN"

    var title: String {
        switch self {
        case .human: "人回"
        case .earth: "地回"
        case .heaven: "天回"
        }
    }

    var relationDescription: String {
        switch self {
        case .human: "人 ↔ 人"
        case .earth: "人 ↔ 接口"
        case .heaven: "接口 ↔ 接口"
        }
    }

}

enum LoopEndpointKind: String, Codable, Hashable, Sendable {
    case human
    case interface
}

/// 类型从当前讨论边界的两个外层端点推导；中间经过的主体和子回不参与分类。
struct LoopBoundary: Codable, Hashable, Sendable {
    let start: LoopEndpointKind
    let end: LoopEndpointKind

    var kind: LoopKind {
        switch (start, end) {
        case (.human, .human): .human
        case (.interface, .interface): .heaven
        case (.human, .interface), (.interface, .human): .earth
        }
    }
}

/// 生命周期独立于 LoopKind；任何类型的回都可能处于这些状态。
enum LoopLifecycleState: String, Codable, CaseIterable, Hashable, Sendable {
    case triggered = "TRIGGERED"
    case matching = "MATCHING"
    case executing = "EXECUTING"
    case waitingHuman = "WAITING_HUMAN"
    case verifying = "VERIFYING"
    case succeeded = "SUCCEEDED"
    case failed = "FAILED"
    case inconclusive = "INCONCLUSIVE"
    case closed = "CLOSED"
    case unknown = "UNKNOWN"

    var title: String {
        switch self {
        case .triggered: "已触发"
        case .matching: "匹配中"
        case .executing: "执行中"
        case .waitingHuman: "等待人工"
        case .verifying: "验证中"
        case .succeeded: "已完成"
        case .failed: "未达到结果"
        case .inconclusive: "无法判断"
        case .closed: "已关闭"
        case .unknown: "状态更新中"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .inconclusive, .closed:
            true
        default:
            false
        }
    }

    static func from(_ raw: String?) -> LoopLifecycleState {
        guard let raw else { return .unknown }
        return LoopLifecycleState(rawValue: raw.uppercased()) ?? .unknown
    }
}
