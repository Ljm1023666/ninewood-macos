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

    func uploadProof(file: MultipartFile) async throws -> String {
        struct Payload: Decodable { let url: String? }
        let payload: Payload = try await client.postMultipart(
            "/certification/uploads/proof",
            fields: [:],
            files: [MultipartFile(
                fieldName: "file",
                fileName: file.fileName,
                mimeType: file.mimeType,
                data: file.data
            )]
        )
        guard let url = payload.url, !url.isEmpty else {
            throw APIError.server(
                statusCode: 500,
                errorCode: nil,
                message: "证明材料上传失败",
                requestID: nil
            )
        }
        return url
    }

    func register(tags: [String], regionId: Int? = nil, proofUrls: [String]? = nil) async throws {
        struct Body: Encodable {
            let tags: [String]
            let regionId: Int?
            let proofUrls: [String]?
        }
        struct OK: Decodable {}
        let _: OK = try await client.post(
            "/certification/register",
            body: Body(tags: tags, regionId: regionId, proofUrls: proofUrls)
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
    /// 与生产端 `UNCONFIGURED_CAPTCHA_TOKEN` 对齐
    static let unconfiguredBypassToken = "unconfigured-bypass"

    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func siteKey() async throws -> String {
        let dto = try await status()
        return dto.siteKey ?? ""
    }

    /// `/captcha` 返回裸 JSON（非 `APIEnvelope`），须走 raw 解码。
    func status() async throws -> CaptchaSiteKeyDTO {
        try await client.getRaw("/captcha")
    }

    /// 开发环境取得 bypass token；正式 hCaptcha 模式必须由 UI 完成挑战。
    func bypassTokenIfAvailable() async throws -> String? {
        let status = try await status()
        let siteKey = status.siteKey ?? ""
        if siteKey.isEmpty || status.mode == "bypass" {
            return Self.unconfiguredBypassToken
        }
        return nil
    }

    /// 将 hCaptcha 浏览器 token 交给 Ninewood 服务端验证，返回一次性发码 token。
    func verifyChallengeToken(_ token: String) async throws -> String {
        struct Body: Encodable { let token: String }
        let result: CaptchaVerifyDTO = try await client.postRaw(
            "/captcha/verify",
            body: Body(token: token)
        )
        guard result.success, !result.token.isEmpty else {
            throw APIError.server(
                statusCode: 400,
                errorCode: "CAPTCHA_FAILED",
                message: result.message ?? "人机验证失败，请重试",
                requestID: nil
            )
        }
        return result.token
    }

    /// 兼容仅开发 bypass 的旧调用点；正式模式要求 UI 提供挑战 token。
    func obtainSendCodeToken() async throws -> String {
        if let token = try await bypassTokenIfAvailable() { return token }
        throw APIError.server(
            statusCode: 428,
            errorCode: "CAPTCHA_REQUIRED",
            message: "请先完成人机验证",
            requestID: nil
        )
    }
}
