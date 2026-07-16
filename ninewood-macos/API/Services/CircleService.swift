import Foundation

@MainActor
final class CircleService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func publicCircles() async throws -> [CircleDTO] {
        let rows: [CircleDTO] = try await client.get("/circles/public")
        if !rows.isEmpty { return rows }
        let page: CirclesListResult = try await client.get("/circles-enhanced")
        return page.circles
    }

    func myCircles() async throws -> [CircleDTO] {
        let memberships: [CircleMembershipDTO] = try await client.get("/circles/my")
        return memberships.compactMap { item in
            guard let circle = item.circle else { return nil }
            return CircleDTO(
                id: circle.id,
                name: circle.name,
                description: circle.description,
                memberCount: circle.memberCount,
                cityCode: circle.cityCode,
                isMember: true,
                role: item.role ?? circle.role,
                coverUrl: circle.coverUrl,
                inviteCode: circle.inviteCode,
                type: circle.type,
                ownerId: circle.ownerId,
                owner: circle.owner
            )
        }
    }

    func get(id: String) async throws -> CircleDTO {
        try await client.get("/circles/\(id)")
    }

    func join(id: String) async throws {
        struct OK: Decodable {}
        let _: OK = try await client.post("/circles/\(id)/join")
    }

    func joinByCode(_ code: String) async throws {
        struct Body: Encodable { let code: String }
        struct OK: Decodable {}
        let _: OK = try await client.post("/circles/join-by-code", body: Body(code: code))
    }

    func create(name: String, description: String?) async throws -> CircleDTO {
        struct Body: Encodable {
            let name: String
            let description: String?
        }
        return try await client.post("/circles", body: Body(name: name, description: description))
    }

    func hubHome(id: String) async throws -> CircleHubHomeDTO {
        try await client.get("/circles/\(id)/hub/home")
    }

    func members(id: String, page: Int = 1) async throws -> [CircleMemberDTO] {
        let pageData: CircleMembersPage = try await client.get(
            "/circles/\(id)/members",
            query: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "limit", value: "50"),
            ]
        )
        return pageData.items
    }

    func resources(id: String) async throws -> [CircleResourceDTO] {
        let page: CircleResourcesPage = try await client.get("/circles/\(id)/resources")
        return page.items ?? page.recent ?? []
    }

    func activities(id: String) async throws -> [CircleActivityDTO] {
        let page: CircleActivitiesPage = try await client.get(
            "/circles/\(id)/hub/activities",
            query: [URLQueryItem(name: "page", value: "1"), URLQueryItem(name: "limit", value: "20")]
        )
        return page.items
    }

    func analytics(id: String, range: String = "30d") async throws -> CircleAnalyticsDTO {
        try await client.get(
            "/circles/\(id)/analytics",
            query: [URLQueryItem(name: "range", value: range)]
        )
    }

    func createInvite(circleId: String, email: String) async throws {
        struct Body: Encodable { let email: String }
        struct OK: Decodable {}
        let _: OK = try await client.post("/circles/\(circleId)/invites", body: Body(email: email))
    }

    func postAnnouncement(circleId: String, title: String, body: String, pinned: Bool = false) async throws {
        struct Body: Encodable {
            let title: String
            let body: String
            let pinned: Bool
        }
        struct OK: Decodable {}
        let _: OK = try await client.post(
            "/circles/\(circleId)/hub/announcements",
            body: Body(title: title, body: body, pinned: pinned)
        )
    }

    func heartbeat(circleId: String) async throws {
        struct OK: Decodable {}
        let _: OK = try await client.post("/circles/\(circleId)/hub/heartbeat")
    }
}
