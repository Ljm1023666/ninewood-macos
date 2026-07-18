import Foundation
import Observation

@Observable
@MainActor
final class OrderDetailFeatureModel {
    private(set) var order: Order
    private(set) var isActing = false
    var actionMessage: String?
    private(set) var lastBreakdown: SettlementBreakdownDTO?

    private let repository: OrderRepository
    private let currentUserID: String?
    private let onUpdated: ((Order) -> Void)?

    init(
        order: Order,
        currentUserID: String?,
        repository: OrderRepository,
        onUpdated: ((Order) -> Void)? = nil
    ) {
        self.order = order
        self.currentUserID = currentUserID
        self.repository = repository
        self.onUpdated = onUpdated
    }

    var isRequester: Bool {
        guard let currentUserID else { return false }
        return order.requesterId.map { $0 == currentUserID }
            ?? (order.demand.publisher.id == currentUserID)
    }

    var isProvider: Bool {
        guard let currentUserID else { return false }
        return order.providerId.map { $0 == currentUserID }
            ?? (order.provider.id == currentUserID)
    }

    var actionPolicy: OrderActionPolicy {
        let role: OrderActorRole = isRequester ? .requester : (isProvider ? .provider : .observer)
        let lifecycle: OrderLifecycle = switch order.stage {
        case .accepted: .accepted
        case .inProgress: .inProgress
        case .waitingReview: .waitingReview
        case .completed: .completed
        case .disputed: .disputed
        case .cancelled: .cancelled
        }
        // 兼容 rawStatus 与 stage 短暂不一致
        let resolved: OrderLifecycle = {
            switch order.rawStatus.uppercased() {
            case "CANCELLED", "REFUNDED": return .cancelled
            case "DISPUTED": return .disputed
            default: return lifecycle
            }
        }()
        return OrderActionPolicy(role: role, lifecycle: resolved, isPrepaid: order.isPrepaid)
    }

    func reload() async {
        do {
            apply(try await repository.detail(id: order.id))
        } catch {
            // 刷新失败时保留可阅读的本地快照；显式动作会展示错误。
        }
    }

    func complete() async {
        await perform {
            try await repository.complete(id: order.id)
            await reload()
            actionMessage = "已标记完成，等待需求方验收"
        }
    }

    func confirm() async -> Bool {
        var shouldReview = false
        await perform {
            let result = try await repository.confirm(id: order.id)
            lastBreakdown = result.breakdown
            await reload()
            actionMessage = result.message ?? "已确认完成并结算"
            shouldReview = true
        }
        return shouldReview
    }

    func cancel() async {
        await perform {
            let wasPrepaid = order.isPrepaid
            try await repository.cancel(id: order.id)
            await reload()
            actionMessage = "订单已取消" + (wasPrepaid ? "（已预付服务费将按规则退还）" : "")
        }
    }

    func applyPaymentResult(message: String, updated: Order?) {
        if let updated {
            apply(updated)
        }
        actionMessage = message
    }

    func applyDisputeResult(message: String) {
        if !message.contains("失败"),
           !message.contains("错误"),
           !message.contains("未登录") {
            var disputed = order
            disputed.stage = .disputed
            disputed.rawStatus = "DISPUTED"
            apply(disputed)
        }
        actionMessage = message.isEmpty ? "已提交争议" : message
    }

    func applyPartialResult(message: String, remainingDemandID: String?) async {
        actionMessage = remainingDemandID.map { "\(message)（余量需求 \($0)）" } ?? message
        await reload()
    }

    private func apply(_ updated: Order) {
        order = updated
        onUpdated?(updated)
    }

    private func perform(_ operation: () async throws -> Void) async {
        guard !isActing else { return }
        isActing = true
        defer { isActing = false }
        do {
            try await operation()
        } catch {
            actionMessage = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
