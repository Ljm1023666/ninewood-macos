import Foundation

@MainActor
final class WelfareService {
    private let client: APIClient
    init(client: APIClient) { self.client = client }

    func list(page: Int = 1) async throws -> [WelfareItemDTO] {
        let pageData: WelfareListPage = try await client.get(
            "/welfare/demands",
            query: [URLQueryItem(name: "page", value: String(page))]
        )
        return pageData.rows
    }

    func claim(demandId: String) async throws {
        struct OK: Decodable {}
        // 生产现行路由：POST /api/welfare/claim/:demandId（非 /welfare/demands/:id/claim）
        let _: OK = try await client.post("/welfare/claim/\(demandId)")
    }

    func rewards(page: Int = 1) async throws -> WelfareRewardsPage {
        try await client.get(
            "/welfare/rewards",
            query: [URLQueryItem(name: "page", value: String(page))]
        )
    }
}
