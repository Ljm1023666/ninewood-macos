import Foundation

@Observable
@MainActor
final class APIClient {
    private(set) var authToken: String?
    private(set) var latestRequestID: String?
    private(set) var serverTimeOffset: TimeInterval = 0
    /// 服务端限流冷却截止时间；冷却期内直接失败，避免转圈狂刷。
    private(set) var rateLimitedUntil: Date?
    var onUnauthorized: (() -> Void)?

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.authToken = KeychainTokenStore.load()
    }

    func setAuthToken(_ token: String?) {
        authToken = token
        if let token {
            KeychainTokenStore.save(token)
        } else {
            KeychainTokenStore.delete()
        }
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await request(path: path, method: "GET", query: query, body: Optional<EmptyJSON>.none)
    }

    /// Agent 等路由返回裸 JSON（无 `{ code, data }` 信封）时使用。
    func getRaw<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await requestRaw(path: path, method: "GET", query: query, body: Optional<EmptyJSON>.none)
    }

    func post<T: Decodable, Body: Encodable>(
        _ path: String,
        body: Body,
        idempotencyKey: String? = nil
    ) async throws -> T {
        try await request(path: path, method: "POST", body: body, idempotencyKey: idempotencyKey)
    }

    func postRaw<T: Decodable, Body: Encodable>(
        _ path: String,
        body: Body,
        idempotencyKey: String? = nil
    ) async throws -> T {
        try await requestRaw(path: path, method: "POST", body: body, idempotencyKey: idempotencyKey)
    }

    func post<T: Decodable>(_ path: String, idempotencyKey: String? = nil) async throws -> T {
        try await request(
            path: path,
            method: "POST",
            body: Optional<EmptyJSON>.none,
            idempotencyKey: idempotencyKey
        )
    }

    func put<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        try await request(path: path, method: "PUT", body: body)
    }

    func patch<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        try await request(path: path, method: "PATCH", body: body)
    }

    func delete<T: Decodable>(_ path: String) async throws -> T {
        try await request(path: path, method: "DELETE", body: Optional<EmptyJSON>.none)
    }

    func deleteRaw<T: Decodable>(_ path: String) async throws -> T {
        try await requestRaw(path: path, method: "DELETE", body: Optional<EmptyJSON>.none)
    }

    func postMultipart<T: Decodable>(
        _ path: String,
        fields: [String: String],
        files: [MultipartFile] = [],
        idempotencyKey: String? = nil
    ) async throws -> T {
        try ensureNotRateLimited()
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        for (key, value) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        for file in files {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append(
                "Content-Disposition: form-data; name=\"\(file.fieldName)\"; filename=\"\(file.fileName)\"\r\n"
                    .data(using: .utf8)!
            )
            body.append("Content-Type: \(file.mimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(file.data)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        guard let url = url(for: path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        prepareCommonHeaders(for: &request, idempotencyKey: idempotencyKey)
        request.httpBody = body
        return try await perform(request)
    }

    func healthCheck() async throws -> Bool {
        // 优先业务健康检查；失败时再探测 API 是否可达（避免偶发代理/网关抖动误判）
        do {
            return try await probeHealthServices()
        } catch let error as APIError {
            // 限流不是“不可达”，必须原样抛出，避免被当成健康或反复重试
            if case .rateLimited = error { throw error }
        } catch {}
        return try await probeAPIReachable()
    }

    private func probeHealthServices() async throws -> Bool {
        try ensureNotRateLimited()
        struct HealthPayload: Decodable { let status: String }
        guard let url = url(for: "/health/services") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = APIConfig.requestTimeout
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        if http.statusCode == 429 {
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            rememberRateLimit(retryAfter: retryAfter)
            throw APIError.rateLimited(
                retryAfter: retryAfter,
                requestID: http.value(forHTTPHeaderField: "X-Request-ID")
            )
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
        let payload = try decoder.decode(HealthPayload.self, from: data)
        return payload.status == "healthy" || payload.status == "degraded"
    }

    /// `/health/services` 不可用时，探测 API 主机是否在线。
    /// 200/401 表示可达；429 必须按限流失败处理，不能伪装成健康。
    private func probeAPIReachable() async throws -> Bool {
        try ensureNotRateLimited()
        guard let url = url(for: "/auth/me") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = APIConfig.requestTimeout
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            if http.statusCode == 429 {
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                rememberRateLimit(retryAfter: retryAfter)
                throw APIError.rateLimited(
                    retryAfter: retryAfter,
                    requestID: http.value(forHTTPHeaderField: "X-Request-ID")
                )
            }
            // 200 已登录可达；401 表示服务在线但未授权——都算云端存活
            return (200 ... 401).contains(http.statusCode)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error)
        }
    }

    private func request<T: Decodable, Body: Encodable>(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        body: Body? = nil,
        idempotencyKey: String? = nil
    ) async throws -> T {
        try await perform(makeURLRequest(path: path, method: method, query: query, body: body, idempotencyKey: idempotencyKey))
    }

    private func requestRaw<T: Decodable, Body: Encodable>(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        body: Body? = nil,
        idempotencyKey: String? = nil
    ) async throws -> T {
        try await performRaw(makeURLRequest(path: path, method: method, query: query, body: body, idempotencyKey: idempotencyKey))
    }

    private func makeURLRequest<Body: Encodable>(
        path: String,
        method: String,
        query: [URLQueryItem],
        body: Body?,
        idempotencyKey: String?
    ) throws -> URLRequest {
        try ensureNotRateLimited()
        guard let url = url(for: path, query: query) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = APIConfig.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        prepareCommonHeaders(for: &request, idempotencyKey: idempotencyKey)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        return request
    }

    private func ensureNotRateLimited() throws {
        guard let until = rateLimitedUntil else { return }
        let remaining = until.timeIntervalSinceNow
        if remaining <= 0 {
            rateLimitedUntil = nil
            return
        }
        throw APIError.rateLimited(retryAfter: remaining, requestID: latestRequestID)
    }

    private func rememberRateLimit(retryAfter: TimeInterval?) {
        let seconds = max(retryAfter ?? 60, 15)
        rateLimitedUntil = Date().addingTimeInterval(min(seconds, 900))
    }

    private func performRaw<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        let responseRequestID = http.value(forHTTPHeaderField: "X-Request-ID")
        latestRequestID = responseRequestID

        if http.statusCode == 401 {
            setAuthToken(nil)
            onUnauthorized?()
            throw APIError.unauthorized
        }

        if http.statusCode == 429 {
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            rememberRateLimit(retryAfter: retryAfter)
            throw APIError.rateLimited(retryAfter: retryAfter, requestID: responseRequestID)
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let failure = try? decoder.decode(APIErrorEnvelope.self, from: data)
            throw APIError.server(
                statusCode: http.statusCode,
                errorCode: failure?.error,
                message: failure?.message ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                requestID: failure?.requestId ?? responseRequestID
            )
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error, requestID: responseRequestID)
        }
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        let responseRequestID = http.value(forHTTPHeaderField: "X-Request-ID")
        latestRequestID = responseRequestID

        if http.statusCode == 401 {
            setAuthToken(nil)
            onUnauthorized?()
            throw APIError.unauthorized
        }

        if http.statusCode == 429 {
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            rememberRateLimit(retryAfter: retryAfter)
            throw APIError.rateLimited(retryAfter: retryAfter, requestID: responseRequestID)
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let failure = try? decoder.decode(APIErrorEnvelope.self, from: data)
            throw APIError.server(
                statusCode: http.statusCode,
                errorCode: failure?.error,
                message: failure?.message ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                requestID: failure?.requestId ?? responseRequestID
            )
        }

        let envelope: APIEnvelope<T>
        do {
            envelope = try decoder.decode(APIEnvelope<T>.self, from: data)
        } catch {
            throw APIError.decoding(error, requestID: responseRequestID)
        }

        latestRequestID = envelope.requestId ?? responseRequestID
        if let serverTimestamp = envelope.timestamp {
            let serverDate = Date(timeIntervalSince1970: TimeInterval(serverTimestamp) / 1_000)
            serverTimeOffset = serverDate.timeIntervalSinceNow
        }

        guard (200 ... 299).contains(envelope.code), let payload = envelope.data else {
            throw APIError.server(
                statusCode: http.statusCode,
                errorCode: nil,
                message: envelope.message,
                requestID: envelope.requestId ?? responseRequestID
            )
        }
        return payload
    }

    var serverNow: Date {
        Date().addingTimeInterval(serverTimeOffset)
    }

    private func prepareCommonHeaders(for request: inout URLRequest, idempotencyKey: String?) {
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        if let authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        if let idempotencyKey, !idempotencyKey.isEmpty {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
    }

    private func url(for path: String, query: [URLQueryItem] = []) -> URL? {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(
            url: APIConfig.baseURL.appendingPathComponent(trimmed),
            resolvingAgainstBaseURL: false
        ) else { return nil }
        if !query.isEmpty {
            components.queryItems = query
        }
        return components.url
    }
}

private struct EmptyJSON: Encodable {}

struct MultipartFile {
    let fieldName: String
    let fileName: String
    let mimeType: String
    let data: Data
}
