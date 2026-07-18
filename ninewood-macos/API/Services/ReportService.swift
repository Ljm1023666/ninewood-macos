import Foundation

@MainActor
final class ReportService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    /// 举报需求。服务端强制要求 `targetUserId`（被举报用户，一般为需求发布者）。
    func report(
        demandId: String,
        category: String,
        reason: String,
        targetUserId: String
    ) async throws {
        struct Body: Encodable {
            let demandId: String
            let category: String
            let reason: String
            let targetUserId: String
        }
        struct OK: Decodable { let id: String? }
        let _: OK = try await client.post(
            "/reports",
            body: Body(
                demandId: demandId,
                category: category,
                reason: reason,
                targetUserId: targetUserId
            )
        )
    }
}
