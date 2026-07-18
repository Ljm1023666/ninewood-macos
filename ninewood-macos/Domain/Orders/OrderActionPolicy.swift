import Foundation

enum OrderActorRole: Hashable, Sendable {
    case requester
    case provider
    case observer
}

enum OrderLifecycle: Hashable, Sendable {
    case accepted
    case inProgress
    case waitingReview
    case completed
    case disputed
    case cancelled
}

enum OrderAllowedAction: Hashable, Sendable {
    case prepayServiceFee
    case markComplete
    case completePartially
    case confirmAndSettle
    case dispute
    case cancel
    case review
    case refresh
}

struct OrderActionPolicy: Sendable {
    let role: OrderActorRole
    let lifecycle: OrderLifecycle
    let isPrepaid: Bool

    var allowedActions: Set<OrderAllowedAction> {
        var actions: Set<OrderAllowedAction> = [.refresh]

        switch (role, lifecycle, isPrepaid) {
        case (.requester, .accepted, _):
            // 接单刚生成、尚未进入履约：仅可取消（若后端允许）或刷新
            actions.insert(.cancel)
        case (.requester, .inProgress, false):
            actions.formUnion([.prepayServiceFee, .cancel])
        case (.requester, .inProgress, true):
            actions.insert(.cancel)
        case (.provider, .inProgress, true):
            actions.formUnion([.markComplete, .completePartially])
        case (.requester, .waitingReview, _):
            actions.formUnion([.confirmAndSettle, .dispute])
        case (_, .completed, _):
            actions.insert(.review)
        case (_, .disputed, _), (_, .cancelled, _):
            break
        default:
            break
        }

        return actions
    }
}

/// 付款预览门控：无有效 breakdown 时禁止确认预付。
enum OrderPaymentGate: Sendable {
    static func canConfirmPrepay(breakdownLoaded: Bool, loadFailed: Bool, payableNow: Decimal, alreadyPrepaid: Bool) -> Bool {
        guard breakdownLoaded, !loadFailed else { return false }
        if alreadyPrepaid { return false }
        return payableNow > 0
    }
}
