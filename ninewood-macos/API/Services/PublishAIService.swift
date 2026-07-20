import Foundation

enum PublishAICardMode: String, Encodable, Sendable {
    case demand = "DEMAND"
    case service = "SERVICE_CARD"
}

struct PublishAnalyzeRequest: Encodable {
    let text: String
    let mode: PublishAICardMode
}

struct PublishAnalyzeEnvelope: Decodable {
    let data: PublishAnalyzeResult?
    let think: String?
    let error: String?
}

struct PublishAnalyzeResult: Decodable, Equatable, Sendable {
    var title: String?
    var summary: String?
    var category: String?
    var serviceType: String?
    var budget: String?
    var schedule: String?
    var confidence: String?
    var missingInfo: [String]?
    var suggestedKeywords: [String]?
    var scopePath: [String]?
    var scopeLabels: [String]?
    var expectedOutcome: String?
    var regionId: Int?
    var readyToPublish: Bool?
    /// Windows analyze / analyze-stream 服务端按 scope 回填
    var taxonomyLeafId: String?

    var effectiveScopeLabels: [String] {
        scopeLabels ?? scopePath ?? []
    }
}

struct PublishAIService {
    let client: APIClient

    func analyzeDemand(text: String, mode: PublishAICardMode) async throws -> PublishAnalyzeResult {
        let envelope: PublishAnalyzeEnvelope = try await client.postRaw(
            "/ai/analyze-demand",
            body: PublishAnalyzeRequest(text: text, mode: mode)
        )
        if let error = envelope.error, !error.isEmpty {
            throw APIError.server(statusCode: 500, errorCode: nil, message: error, requestID: nil)
        }
        guard let data = envelope.data else {
            throw APIError.server(statusCode: 500, errorCode: nil, message: "AI 未返回结构化结果", requestID: nil)
        }
        return data
    }
}
