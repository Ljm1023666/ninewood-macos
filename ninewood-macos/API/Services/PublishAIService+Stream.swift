import Foundation

struct PublishRequirementState: Encodable, Sendable {
    var confirmed: [String: String]
    var pending: [String]
}

struct PublishAnalyzeStreamRequest: Encodable, Sendable {
    let message: String
    let requirementState: PublishRequirementState
    let thinkMode: Bool
    let mode: PublishAICardMode
}

struct PublishAgentChatMessage: Encodable, Sendable {
    let role: String
    let content: String
    let reasoningContent: String?

    enum CodingKeys: String, CodingKey {
        case role, content
        case reasoningContent = "reasoning_content"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(role, forKey: .role)
        try c.encode(content, forKey: .content)
        if let reasoningContent, !reasoningContent.isEmpty {
            try c.encode(reasoningContent, forKey: .reasoningContent)
        }
    }
}

extension PublishAIService {
    /// Windows `POST /api/ai/agent-demand-stream`
    func streamAgentDemand(
        messages: [PublishAgentChatMessage],
        mode: PublishAICardMode,
        thinkMode: Bool = false,
        onEvent: @escaping @Sendable (String, [String: Any]) -> Void,
        onDone: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) -> Task<Void, Never> {
        let token = client.authToken
        return Task {
            do {
                let url = APIConfig.baseURL.appendingPathComponent("ai/agent-demand-stream")
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 180
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                if let token {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                let body: [String: Any] = [
                    "messages": messages.map { msg -> [String: Any] in
                        var dict: [String: Any] = [
                            "role": msg.role,
                            "content": msg.content,
                        ]
                        if let reasoning = msg.reasoningContent, !reasoning.isEmpty {
                            dict["reasoning_content"] = reasoning
                        }
                        return dict
                    },
                    "thinkMode": thinkMode,
                    "mode": mode.rawValue,
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                try await Self.consumeSSE(
                    request: request,
                    failureMessage: "AI 整理流失败",
                    onEvent: onEvent
                )
                onDone()
            } catch {
                if error is CancellationError {
                    onDone()
                    return
                }
                onError(error)
            }
        }
    }

    /// Windows `syncWorkspaceFromConversation` → `POST /api/ai/analyze-demand-stream`
    /// 全量用户 transcript + `requirementState`；消费 SSE `result`。
    func syncAnalyzeFromConversation(
        messages: [PublishAgentChatMessage],
        mode: PublishAICardMode,
        requirementState: PublishRequirementState
    ) async throws -> PublishAnalyzeResult {
        let userText = messages
            .filter { $0.role == "user" }
            .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !userText.isEmpty else {
            throw APIError.server(statusCode: 400, errorCode: nil, message: "请输入需求描述", requestID: nil)
        }

        let token = client.authToken
        let url = APIConfig.baseURL.appendingPathComponent("ai/analyze-demand-stream")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let body = PublishAnalyzeStreamRequest(
            message: userText,
            requirementState: requirementState,
            thinkMode: false,
            mode: mode
        )
        request.httpBody = try JSONEncoder().encode(body)

        var resultPayload: [String: Any]?
        try await Self.consumeSSE(
            request: request,
            failureMessage: "工作区同步失败",
            onEvent: { event, obj in
                if event == "result" {
                    resultPayload = obj
                }
            }
        )

        guard let payload = resultPayload else {
            throw APIError.server(
                statusCode: 500,
                errorCode: nil,
                message: "AI 未返回结构化结果",
                requestID: nil
            )
        }
        return Self.decodeAnalyzeResult(payload)
    }

    /// Speed 模式仍走 Windows `/ai/analyze-demand`，但用 180s 超时（避免 APIClient 默认 15s）。
    func analyzeDemandLongTimeout(text: String, mode: PublishAICardMode) async throws -> PublishAnalyzeResult {
        let token = client.authToken
        let url = APIConfig.baseURL.appendingPathComponent("ai/analyze-demand")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(PublishAnalyzeRequest(text: text, mode: mode))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(statusCode: 500, errorCode: nil, message: "AI 无响应", requestID: nil)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(PublishAnalyzeEnvelope.self, from: data))?.error
                ?? "AI 分析失败"
            throw APIError.server(statusCode: http.statusCode, errorCode: nil, message: message, requestID: nil)
        }
        let envelope = try JSONDecoder().decode(PublishAnalyzeEnvelope.self, from: data)
        if let error = envelope.error, !error.isEmpty {
            throw APIError.server(statusCode: 500, errorCode: nil, message: error, requestID: nil)
        }
        guard let result = envelope.data else {
            throw APIError.server(statusCode: 500, errorCode: nil, message: "AI 未返回结构化结果", requestID: nil)
        }
        return result
    }

    private static func consumeSSE(
        request: URLRequest,
        failureMessage: String,
        onEvent: @escaping @Sendable (String, [String: Any]) -> Void
    ) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw APIError.server(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500,
                errorCode: nil,
                message: failureMessage,
                requestID: nil
            )
        }

        var event = "message"
        var dataLines: [String] = []
        for try await line in bytes.lines {
            if Task.isCancelled { throw CancellationError() }
            if line.isEmpty {
                if !dataLines.isEmpty {
                    let raw = dataLines.joined(separator: "\n")
                    if let obj = parseJSONObject(raw) {
                        onEvent(event, obj)
                    } else if event == "text" {
                        onEvent(event, ["delta": raw])
                    } else if event == "result", let obj = parseJSONObject(raw) {
                        onEvent(event, obj)
                    }
                    // done / think-end / meta 非 JSON：忽略
                    dataLines.removeAll()
                }
                event = "message"
                continue
            }
            if line.hasPrefix("event:") {
                event = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
        }
        if !dataLines.isEmpty, let obj = parseJSONObject(dataLines.joined(separator: "\n")) {
            onEvent(event, obj)
        }
    }

    private static func parseJSONObject(_ raw: String) -> [String: Any]? {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    /// 对齐 Windows `normalizeAnalyzePayload`
    private static func decodeAnalyzeResult(_ raw: [String: Any]) -> PublishAnalyzeResult {
        let scopeLabels = stringArray(raw["scopeLabels"]) ?? stringArray(raw["scopePath"])
        let regionRaw = raw["regionId"]
        let regionId: Int? = {
            if regionRaw == nil || regionRaw is NSNull { return nil }
            if let n = regionRaw as? Int { return n }
            if let n = regionRaw as? Double { return Int(n) }
            if let s = regionRaw as? String, let n = Int(s) { return n }
            return nil
        }()

        return PublishAnalyzeResult(
            title: raw["title"] as? String,
            summary: raw["summary"] as? String,
            category: raw["category"] as? String,
            serviceType: raw["serviceType"] as? String,
            budget: raw["budget"] as? String,
            schedule: raw["schedule"] as? String,
            confidence: raw["confidence"] as? String,
            missingInfo: stringArray(raw["missingInfo"]),
            suggestedKeywords: stringArray(raw["suggestedKeywords"]),
            scopePath: stringArray(raw["scopePath"]),
            scopeLabels: scopeLabels,
            expectedOutcome: raw["expectedOutcome"] as? String,
            regionId: regionId,
            readyToPublish: raw["readyToPublish"] as? Bool,
            taxonomyLeafId: raw["taxonomyLeafId"] as? String
        )
    }

    private static func stringArray(_ value: Any?) -> [String]? {
        guard let arr = value as? [Any] else { return nil }
        let strings = arr.compactMap { $0 as? String }
        return strings
    }
}
