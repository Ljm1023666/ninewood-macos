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
        let _: OK = try await client.post("/welfare/demands/\(demandId)/claim")
    }

    func rewards(page: Int = 1) async throws -> [WelfareItemDTO] {
        let pageData: WelfareListPage = try await client.get(
            "/welfare/rewards",
            query: [URLQueryItem(name: "page", value: String(page))]
        )
        return pageData.rows
    }
}
