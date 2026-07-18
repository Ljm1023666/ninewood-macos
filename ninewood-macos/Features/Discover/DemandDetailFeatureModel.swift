import Foundation
import Observation

@Observable
@MainActor
final class DemandDetailFeatureModel {
    private(set) var demand: Demand
    private(set) var isFavoriting = false
    private(set) var isFavorited = false
    private(set) var isSnatching = false
    private(set) var isRefreshing = false
    var actionMessage: String?
    var actionError: String?
    private(set) var refreshError: String?

    private var demandRepository: DemandRepository?
    private var userRepository: UserRepository?

    init(demand: Demand) {
        self.demand = demand
    }

    func configure(
        demandRepository: DemandRepository,
        userRepository: UserRepository
    ) {
        self.demandRepository = demandRepository
        self.userRepository = userRepository
    }

    func load() async {
        async let detail: Void = refresh()
        async let favorite: Void = loadFavoriteState()
        _ = await (detail, favorite)
    }

    func refresh() async {
        guard let demandRepository, !isRefreshing else { return }
        isRefreshing = true
        refreshError = nil
        defer { isRefreshing = false }
        do {
            demand = try await demandRepository.detail(id: demand.id)
        } catch {
            refreshError = Self.message(for: error)
        }
    }

    func loadFavoriteState() async {
        guard let userRepository else { return }
        isFavorited = (try? await userRepository.isFavorite(demandID: demand.id)) ?? isFavorited
    }

    func toggleFavorite() async {
        guard let userRepository, !isFavoriting else { return }
        isFavoriting = true
        defer { isFavoriting = false }
        do {
            try await userRepository.toggleFavorite(demandID: demand.id)
            isFavorited.toggle()
            actionMessage = isFavorited ? "已收藏需求" : "已取消收藏"
        } catch {
            actionError = Self.message(for: error)
        }
    }

    func snatch() async {
        guard let demandRepository, !isSnatching else { return }
        isSnatching = true
        defer { isSnatching = false }
        do {
            try await demandRepository.takeImmediately(id: demand.id)
            actionMessage = "抢单成功"
            await refresh()
        } catch {
            actionError = Self.message(for: error)
        }
    }

    func apply(reason: String) async {
        guard let demandRepository else { return }
        do {
            _ = try await demandRepository.request(
                demandID: demand.id,
                message: reason,
                idempotencyKey: UUID().uuidString
            )
            actionMessage = "已提交请求接单，可等待发布者沟通"
        } catch {
            actionError = Self.message(for: error)
        }
    }

    func bid(price: Decimal?, message: String) async {
        guard let demandRepository else { return }
        do {
            try await demandRepository.bid(
                demandID: demand.id,
                offerPrice: price,
                message: message
            )
            actionMessage = "已提交应标"
        } catch {
            actionError = Self.message(for: error)
        }
    }

    func clearFeedback() {
        actionMessage = nil
        actionError = nil
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
