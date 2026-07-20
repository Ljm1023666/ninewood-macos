import Foundation

@MainActor
final class LoopService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func recommend(
        query: String = "",
        paths: [String] = [],
        facets: [String] = [],
        limit: Int = 10
    ) async throws -> LoopRecommendationResultDTO {
        var queryItems = [URLQueryItem]()
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        if !paths.isEmpty {
            queryItems.append(URLQueryItem(name: "paths", value: paths.joined(separator: ",")))
        }
        if !facets.isEmpty {
            queryItems.append(URLQueryItem(name: "facets", value: facets.joined(separator: ",")))
        }
        queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        return try await client.get(
            "/loops/recommend",
            query: queryItems
        )
    }

    /// 移动端只向人展示地回；天回不对人搜索。
    func recommendEarth(query: String, limit: Int = 10) async throws -> LoopRecommendationResultDTO {
        let result = try await recommend(query: query, limit: limit)
        let earthItems = result.items.filter { $0.loopKind.uppercased() == "EARTH" }
        return LoopRecommendationResultDTO(
            query: result.query,
            resolved: result.resolved,
            items: earthItems,
            humanFallback: earthItems.isEmpty ? result.humanFallback : nil
        )
    }

    func listOfferings(
        loopKind: String? = nil,
        query: String? = nil,
        paths: [String] = [],
        limit: Int = 20
    ) async throws -> [LoopOfferingItemDTO] {
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let loopKind { items.append(URLQueryItem(name: "loopKind", value: loopKind)) }
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        if !paths.isEmpty {
            items.append(URLQueryItem(name: "paths", value: paths.joined(separator: ",")))
        }
        return try await client.get("/loops/offerings", query: items)
    }

    func getOffering(id: String) async throws -> LoopOfferingItemDTO {
        try await client.get("/loops/offerings/\(id)")
    }

    func runOffering(id: String, demandId: String? = nil, input: [String: String] = [:]) async throws -> LoopRunOfferingResultDTO {
        struct Body: Encodable {
            let demandId: String?
            let input: [String: String]?
        }
        return try await client.post(
            "/loops/offerings/\(id)/run",
            body: Body(demandId: demandId, input: input.isEmpty ? nil : input)
        )
    }

    func getRun(id: String) async throws -> LoopRunDetailDTO {
        try await client.get("/loops/runs/\(id)")
    }

    func getRunEvents(id: String) async throws -> [LoopEventDTO] {
        try await client.get("/loops/runs/\(id)/events")
    }

    func runs(demandId: String) async throws -> [LoopRunDetailDTO] {
        try await client.get(
            "/loops/runs",
            query: [URLQueryItem(name: "demandId", value: demandId)]
        )
    }

    func myRuns(
        kind: String? = nil,
        kinds: [String] = [],
        status: String? = nil,
        sort: String = "recent",
        limit: Int = 20
    ) async throws -> MyLoopsResultDTO {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let kind { query.append(URLQueryItem(name: "kind", value: kind)) }
        if !kinds.isEmpty {
            query.append(URLQueryItem(name: "kinds", value: kinds.joined(separator: ",")))
        }
        if let status { query.append(URLQueryItem(name: "status", value: status)) }
        query.append(URLQueryItem(name: "sort", value: sort))
        return try await client.get("/loops/runs/mine", query: query)
    }

    func heavenCapabilities() async throws -> [HeavenCapabilityDTO] {
        try await client.get("/loops/capabilities")
    }

    func retryVerification(runId: String) async throws -> LoopRetryVerificationResultDTO {
        try await client.post("/loops/runs/\(runId)/retry-verification")
    }
}
