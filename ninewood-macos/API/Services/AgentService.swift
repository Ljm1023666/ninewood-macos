import Foundation

private struct AgentSSEServerError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

// MARK: - DTOs

struct AgentConversationDTO: Decodable, Identifiable, Hashable {
    let id: String
    let title: String?
    let thinkMode: Bool?
    let createdAt: String?
    let updatedAt: String?
    let lastMessagePreview: String?
    let messageCount: Int?

    init(
        id: String,
        title: String?,
        thinkMode: Bool?,
        createdAt: String?,
        updatedAt: String?,
        lastMessagePreview: String?,
        messageCount: Int?
    ) {
        self.id = id
        self.title = title
        self.thinkMode = thinkMode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastMessagePreview = lastMessagePreview
        self.messageCount = messageCount
    }

    enum CodingKeys: String, CodingKey {
        case id, title, thinkMode, createdAt, updatedAt, lastMessagePreview, messageCount
        case count = "_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        thinkMode = try c.decodeIfPresent(Bool.self, forKey: .thinkMode)
        createdAt = try Self.decodeDateString(c, forKey: .createdAt)
        updatedAt = try Self.decodeDateString(c, forKey: .updatedAt)
        lastMessagePreview = try c.decodeIfPresent(String.self, forKey: .lastMessagePreview)
        if let count = try c.decodeIfPresent(Int.self, forKey: .messageCount) {
            messageCount = count
        } else if let nested = try? c.nestedContainer(keyedBy: CountKeys.self, forKey: .count) {
            messageCount = try nested.decodeIfPresent(Int.self, forKey: .messages)
        } else {
            messageCount = nil
        }
    }

    private enum CountKeys: String, CodingKey { case messages }

    private static func decodeDateString(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> String? {
        if let s = try c.decodeIfPresent(String.self, forKey: key) { return s }
        return nil
    }
}

struct AgentMessageDTO: Decodable, Identifiable, Hashable {
    let id: String
    let role: String
    let content: String
    let thinking: String?
    let createdAt: String?

    init(id: String, role: String, content: String, thinking: String? = nil, createdAt: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.thinking = thinking
        self.createdAt = createdAt
    }
}

struct AgentConversationDetailDTO: Decodable {
    let id: String
    let title: String?
    let thinkMode: Bool?
    let createdAt: String?
    let updatedAt: String?
    let messages: [AgentMessageDTO]

    init(
        id: String,
        title: String?,
        thinkMode: Bool?,
        createdAt: String?,
        updatedAt: String?,
        messages: [AgentMessageDTO]
    ) {
        self.id = id
        self.title = title
        self.thinkMode = thinkMode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        thinkMode = try container.decodeIfPresent(Bool.self, forKey: .thinkMode)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        messages = try container.decodeIfPresent([AgentMessageDTO].self, forKey: .messages) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, thinkMode, createdAt, updatedAt, messages
    }
}

struct AgentConversationsListDTO: Decodable {
    let conversations: [AgentConversationDTO]
}

struct AgentSendMessageResponseDTO: Decodable {
    let success: Bool?
    let userMessage: AgentMessageDTO?
    let assistantMessage: AgentMessageDTO?
    let message: AgentMessageDTO?
    let reply: AgentMessageDTO?

    var assistantReply: AgentMessageDTO? {
        assistantMessage ?? reply ?? (message?.role == "assistant" ? message : nil)
    }
}

struct AgentApproveToolResponseDTO: Decodable {
    let success: Bool?
    let approved: Bool?
    let message: String?
    let error: String?
    let data: AgentApproveToolDataDTO?
}

struct AgentApproveToolDataDTO: Decodable {
    let path: String?
}

// MARK: - Service

@MainActor
final class AgentService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func listConversations() async throws -> [AgentConversationDTO] {
        let page: AgentConversationsListDTO = try await client.getRaw("/agent/conversations")
        return page.conversations
    }

    func getConversation(id: String) async throws -> AgentConversationDetailDTO {
        try await client.getRaw("/agent/conversations/\(id)")
    }

    func createConversation(title: String? = nil, thinkMode: Bool? = true) async throws -> AgentConversationDTO {
        struct Body: Encodable {
            let title: String?
            let thinkMode: Bool?
        }
        return try await client.postRaw(
            "/agent/conversations",
            body: Body(title: title, thinkMode: thinkMode ?? true)
        )
    }

    func deleteConversation(id: String) async throws {
        struct OK: Decodable { let success: Bool? }
        let _: OK = try await client.deleteRaw("/agent/conversations/\(id)")
    }

    func sendMessageNonStream(id: String, message: String) async throws -> AgentSendMessageResponseDTO {
        struct Body: Encodable { let message: String }
        return try await client.postRaw("/agent/conversations/\(id)/messages", body: Body(message: message))
    }

    @discardableResult
    func approveTool(
        conversationId: String,
        toolCallId: String,
        approved: Bool
    ) async throws -> AgentApproveToolResponseDTO {
        struct Body: Encodable {
            let toolCallId: String
            let approved: Bool
        }
        return try await client.postRaw(
            "/agent/conversations/\(conversationId)/approve-tool",
            body: Body(toolCallId: toolCallId, approved: approved)
        )
    }

    /// Streams assistant reply via SSE. Returns a cancellable task.
    /// - Parameter model: Optional Ollama / provider model name; when set, cloud `executeAgent` uses it instead of default `AI_MODEL`.
    @discardableResult
    func streamReply(
        conversationId: String,
        message: String,
        thinkMode: Bool? = nil,
        model: String? = nil,
        onEvent: @escaping @MainActor @Sendable (String, String) -> Void,
        onDone: @escaping @MainActor @Sendable () -> Void,
        onError: @escaping @MainActor @Sendable (Error) -> Void
    ) -> Task<Void, Never> {
        let token = client.authToken
        return Task {
            do {
                let trimmed = conversationId.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                // 必须用 appendingPathComponent：relativeTo 无尾斜杠的 /api 会把路径解析成 /agent/...（丢掉 api）
                let url = APIConfig.baseURL
                    .appendingPathComponent("agent")
                    .appendingPathComponent("conversations")
                    .appendingPathComponent(trimmed)
                    .appendingPathComponent("stream")

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 300
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
                if let token {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }

                struct StreamBody: Encodable {
                    let message: String
                    let thinkMode: Bool
                    let accessMode: String
                    let model: String?

                    func encode(to encoder: Encoder) throws {
                        var c = encoder.container(keyedBy: CodingKeys.self)
                        try c.encode(message, forKey: .message)
                        try c.encode(thinkMode, forKey: .thinkMode)
                        try c.encode(accessMode, forKey: .accessMode)
                        try c.encodeIfPresent(model, forKey: .model)
                    }

                    private enum CodingKeys: String, CodingKey {
                        case message, thinkMode, accessMode, model
                    }
                }
                let encoder = JSONEncoder()
                let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
                request.httpBody = try encoder.encode(
                    StreamBody(
                        message: message,
                        thinkMode: thinkMode ?? true,
                        accessMode: "approval",
                        model: (trimmedModel?.isEmpty == false) ? trimmedModel : nil
                    )
                )

                let (bytes, response) = try await URLSession.shared.bytes(for: request)

                guard let http = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }
                if http.statusCode == 401 {
                    throw APIError.unauthorized
                }
                if http.statusCode == 429 {
                    var preview = Data()
                    for try await byte in bytes {
                        preview.append(byte)
                        if preview.count >= 2048 { break }
                    }
                    let retryAfter = Self.retryAfterSeconds(http: http, data: preview)
                    await MainActor.run {
                        client.noteRateLimited(retryAfter: retryAfter)
                    }
                    throw APIError.rateLimited(
                        retryAfter: retryAfter,
                        requestID: http.value(forHTTPHeaderField: "X-Request-ID")
                    )
                }
                guard (200 ... 299).contains(http.statusCode) else {
                    throw APIError.server(
                        statusCode: http.statusCode,
                        errorCode: nil,
                        message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                        requestID: http.value(forHTTPHeaderField: "X-Request-ID")
                    )
                }

                var currentEvent = "message"
                var dataLines: [String] = []

                @MainActor
                func deliverEvent(_ event: String, data: String) throws {
                    let normalized = event.lowercased().replacingOccurrences(of: "-", with: "_")
                    guard normalized == "error" else {
                        onEvent(event, data)
                        return
                    }

                    var message = data
                    if let jsonData = data.data(using: .utf8),
                       let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       let serverMessage = object["message"] as? String,
                       !serverMessage.isEmpty {
                        message = serverMessage
                    }
                    throw AgentSSEServerError(message: message.isEmpty ? "Agent stream failed" : message)
                }

                for try await line in bytes.lines {
                    if Task.isCancelled { return }

                    if line.isEmpty {
                        if !dataLines.isEmpty {
                            try deliverEvent(currentEvent, data: dataLines.joined(separator: "\n"))
                            dataLines.removeAll()
                        }
                        currentEvent = "message"
                        continue
                    }

                    if line.hasPrefix("event:") {
                        currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                    } else if line.hasPrefix("data:") {
                        dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                    } else if !line.hasPrefix(":") {
                        dataLines.append(line)
                    }
                }

                if !dataLines.isEmpty {
                    try deliverEvent(currentEvent, data: dataLines.joined(separator: "\n"))
                }
                if !Task.isCancelled {
                    onDone()
                }
            } catch {
                if !Task.isCancelled {
                    onError(error)
                }
            }
        }
    }

    private static func retryAfterSeconds(http: HTTPURLResponse, data: Data) -> TimeInterval? {
        if let header = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init), header > 0 {
            return header
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let ms = object["cooldownMs"] as? Double, ms > 0 { return ms / 1000 }
        if let ms = object["cooldownMs"] as? Int, ms > 0 { return TimeInterval(ms) / 1000 }
        if let seconds = object["retryAfter"] as? Double, seconds > 0 { return seconds }
        if let seconds = object["retryAfter"] as? Int, seconds > 0 { return TimeInterval(seconds) }
        return nil
    }
}
