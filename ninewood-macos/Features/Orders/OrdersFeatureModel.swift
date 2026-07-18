import Foundation
import Observation

@Observable
@MainActor
final class OrdersFeatureModel {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "全部"
        case inProgress = "进行中"
        case waiting = "待验收"
        case completed = "已完成"
        case disputed = "争议"
        var id: String { rawValue }
    }

    enum RoleFilter: String, CaseIterable, Identifiable {
        case all = "全部角色"
        case requester = "我是需求方"
        case provider = "我是服务方"
        var id: String { rawValue }

        var apiRole: String? {
            switch self {
            case .all: nil
            case .requester: "requester"
            case .provider: "provider"
            }
        }
    }

    var filter: Filter = .all
    var roleFilter: RoleFilter = .all
    private(set) var orders: [Order] = []
    var selected: Order?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let repository: OrderRepository
    private let isPreview: Bool

    init(repository: OrderRepository, previewOrders: [Order]? = nil) {
        self.repository = repository
        self.isPreview = previewOrders != nil
        self.orders = previewOrders ?? []
        self.selected = previewOrders?.first
    }

    var filteredOrders: [Order] {
        switch filter {
        case .all:
            orders
        case .inProgress:
            orders.filter { $0.stage == .inProgress || $0.stage == .accepted }
        case .waiting:
            orders.filter { $0.stage == .waitingReview }
        case .completed:
            orders.filter { $0.stage == .completed }
        case .disputed:
            orders.filter { $0.stage == .disputed }
        }
    }

    func load() async {
        if isPreview { return }
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let rows = try await repository.list(role: roleFilter.apiRole)
            orders = rows
            if let selectedID = selected?.id {
                selected = rows.first(where: { $0.id == selectedID }) ?? rows.first
            } else {
                selected = rows.first
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func apply(_ updated: Order) {
        if let index = orders.firstIndex(where: { $0.id == updated.id }) {
            orders[index] = updated
        }
        selected = updated
    }
}
