import Foundation

@MainActor
final class ServiceCardService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func search(keyword: String? = nil, limit: Int = 20) async throws -> [ServiceCardDTO] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let keyword, !keyword.isEmpty {
            query.append(URLQueryItem(name: "keyword", value: keyword))
        }
        return try await client.get("/service-cards/search", query: query)
    }

    func mine() async throws -> [ServiceCardDTO] {
        try await client.get("/service-cards/mine")
    }

    func get(id: String) async throws -> ServiceCardDTO {
        try await client.get("/service-cards/\(id)")
    }

    func create(_ input: ServiceCardInputBody) async throws -> ServiceCardDTO {
        try await client.post("/service-cards", body: input)
    }

    func update(id: String, _ input: ServiceCardInputBody) async throws -> ServiceCardDTO {
        try await client.patch("/service-cards/\(id)", body: input)
    }

    func publish(id: String) async throws -> ServiceCardDTO {
        try await client.post("/service-cards/\(id)/publish")
    }

    func unpublish(id: String) async throws -> ServiceCardDTO {
        try await client.post("/service-cards/\(id)/unpublish")
    }
}

@MainActor
final class ReviewService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func create(orderId: String, rating: Int, content: String?) async throws {
        struct Body: Encodable {
            let orderId: String
            let rating: Int
            let content: String?
        }
        struct OK: Decodable {}
        let _: OK = try await client.post(
            "/reviews",
            body: Body(orderId: orderId, rating: rating, content: content)
        )
    }
}

@MainActor
final class RegionService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func children(parentId: Int? = nil) async throws -> [RegionDTO] {
        var query: [URLQueryItem] = []
        if let parentId {
            query.append(URLQueryItem(name: "parentId", value: String(parentId)))
        }
        return try await client.get("/regions", query: query)
    }

    func search(q: String) async throws -> [RegionDTO] {
        try await client.get("/regions/search", query: [URLQueryItem(name: "q", value: q)])
    }
}

@MainActor
final class TagService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func list(q: String? = nil) async throws -> [TagDTO] {
        var query: [URLQueryItem] = []
        if let q { query.append(URLQueryItem(name: "q", value: q)) }
        return try await client.get("/tags", query: query)
    }
}

@MainActor
final class CertificationService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func register(tags: [String], regionId: Int? = nil) async throws {
        struct Body: Encodable {
            let tags: [String]
            let regionId: Int?
        }
        struct OK: Decodable {}
        let _: OK = try await client.post(
            "/certification/register",
            body: Body(tags: tags, regionId: regionId)
        )
    }

    func status() async throws -> CertStatusDTO {
        try await client.get("/users/cert-status")
    }

    func upgrade() async throws {
        struct OK: Decodable {}
        let _: OK = try await client.post("/users/upgrade-cert")
    }

    func providers(tags: String? = nil, regionId: Int? = nil, page: Int = 1) async throws -> [SoftUserDTO] {
        var query = [URLQueryItem(name: "page", value: String(page))]
        if let tags { query.append(URLQueryItem(name: "tags", value: tags)) }
        if let regionId { query.append(URLQueryItem(name: "regionId", value: String(regionId))) }
        // 兼容数组或分页
        if let rows: [SoftUserDTO] = try? await client.get("/certification/providers", query: query) {
            return rows
        }
        let pageData: UserListPage = try await client.get("/certification/providers", query: query)
        return pageData.rows
    }
}

@MainActor
final class CaptchaService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func siteKey() async throws -> String {
        let dto: CaptchaSiteKeyDTO = try await client.get("/captcha")
        return dto.siteKey ?? ""
    }
}
