import Foundation

@MainActor
final class NaturalLoopRepository {
    enum MineSort: String, Sendable {
        case recent
        case completion
        case success
    }

    private let service: LoopService
    private let mapper: NaturalLoopMapper

    init(service: LoopService, mapper: NaturalLoopMapper = NaturalLoopMapper()) {
        self.service = service
        self.mapper = mapper
    }

    func recommend(
        query: String = "",
        paths: [String] = [],
        facets: [String] = [],
        limit: Int = 20
    ) async throws -> NaturalLoopRecommendations {
        let dto = try await service.recommend(
            query: query,
            paths: paths,
            facets: facets,
            limit: limit
        )
        return try mapper.recommendations(from: dto)
    }

    func offerings(
        boundaryKind: NaturalLoopBoundaryKind? = nil,
        query: String? = nil,
        paths: [String] = [],
        limit: Int = 20
    ) async throws -> [NaturalLoopOffering] {
        let dtos = try await service.listOfferings(
            loopKind: boundaryKind?.rawValue,
            query: query,
            paths: paths,
            limit: limit
        )
        return try dtos.map(mapper.offering)
    }

    func offering(id: String) async throws -> NaturalLoopOffering {
        try mapper.offering(from: await service.getOffering(id: id))
    }

    func run(
        offeringID: String,
        demandID: String? = nil,
        input: [String: String] = [:]
    ) async throws -> NaturalLoopExecution {
        let result = try await service.runOffering(
            id: offeringID,
            demandId: demandID,
            input: input
        )
        let hydratedRun: NaturalLoopRun?
        if let runID = result.runId {
            hydratedRun = try await detail(id: runID)
        } else {
            hydratedRun = nil
        }
        return mapper.execution(from: result, hydratedRun: hydratedRun)
    }

    func mine(
        boundaryKinds: [NaturalLoopBoundaryKind] = [],
        status: NaturalLoopStage? = nil,
        sort: MineSort = .recent,
        limit: Int = 100
    ) async throws -> NaturalLoopRunCollection {
        let result = try await service.myRuns(
            kinds: boundaryKinds.map(\.rawValue),
            status: status?.backendValue,
            sort: sort.rawValue,
            limit: limit
        )
        return try mapper.runCollection(from: result)
    }

    func detail(id: String) async throws -> NaturalLoopRun {
        try mapper.run(from: await service.getRun(id: id))
    }

    func evidence(runID: String) async throws -> [LoopEvidence] {
        try await service.getRunEvents(id: runID).map(mapper.evidence)
    }

    @discardableResult
    func retryVerification(runID: String) async throws -> NaturalLoopRun {
        _ = try await service.retryVerification(runId: runID)
        return try await detail(id: runID)
    }
}
