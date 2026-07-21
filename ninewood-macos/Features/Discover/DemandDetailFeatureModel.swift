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
    /// 切换需求时递增，用于丢弃过期的 detail / favorite 回写。
    private var loadGeneration = 0

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

    /// 列表点选时立刻换成本地快照，避免整页 remount 抖动。
    func replace(with demand: Demand) {
        guard self.demand.id != demand.id else {
            self.demand = demand
            return
        }
        loadGeneration += 1
        self.demand = demand
        refreshError = nil
        actionMessage = nil
        actionError = nil
        isFavorited = false
        isRefreshing = false
        isFavoriting = false
        isSnatching = false
    }

    func load(surfaceRefreshError: Bool = false) async {
        let generation = loadGeneration
        let demandID = demand.id
        async let detail: Void = refresh(surfaceError: surfaceRefreshError, generation: generation, demandID: demandID)
        async let favorite: Void = loadFavoriteState(generation: generation, demandID: demandID)
        _ = await (detail, favorite)
    }

    func refresh(surfaceError: Bool = true) async {
        await refresh(surfaceError: surfaceError, generation: loadGeneration, demandID: demand.id)
    }

    private func refresh(surfaceError: Bool, generation: Int, demandID: String) async {
        guard let demandRepository else { return }
        if generation == loadGeneration {
            isRefreshing = true
            if surfaceError { refreshError = nil }
        }
        defer {
            if generation == loadGeneration {
                isRefreshing = false
            }
        }
        do {
            let fresh = try await demandRepository.detail(id: demandID)
            guard generation == loadGeneration, demand.id == demandID else { return }
            demand = fresh
            refreshError = nil
        } catch {
            guard generation == loadGeneration, demand.id == demandID else { return }
            // 自动切换时保留列表快照，不把「需求不存在」刷成红条抖动。
            if surfaceError {
                refreshError = Self.message(for: error)
            }
        }
    }

    func loadFavoriteState() async {
        await loadFavoriteState(generation: loadGeneration, demandID: demand.id)
    }

    private func loadFavoriteState(generation: Int, demandID: String) async {
        guard let userRepository else { return }
        let favorited = (try? await userRepository.isFavorite(demandID: demandID)) ?? false
        guard generation == loadGeneration, demand.id == demandID else { return }
        isFavorited = favorited
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
