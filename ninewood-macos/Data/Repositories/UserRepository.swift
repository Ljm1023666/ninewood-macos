import Foundation

/// 用户关系类数据入口。当前先承接收藏，后续个人资料与关注关系可继续收口到这里。
@MainActor
final class UserRepository {
    private let service: UserService

    init(service: UserService) {
        self.service = service
    }

    func isFavorite(demandID: String) async throws -> Bool {
        let page = try await service.favorites()
        return page.demands.contains { $0.id == demandID }
    }

    func toggleFavorite(demandID: String) async throws {
        try await service.toggleFavorite(demandId: demandID)
    }
}
