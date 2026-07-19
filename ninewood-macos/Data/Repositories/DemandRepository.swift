import Foundation

/// 需求领域的数据入口。View / FeatureModel 不再直接依赖路由级 Service。
@MainActor
final class DemandRepository: DemandDiscovering {
    private let service: DemandService

    init(service: DemandService) {
        self.service = service
    }

    func discover(
        page: Int = 1,
        limit: Int = 20,
        keyword: String? = nil,
        lat: Double? = nil,
        lng: Double? = nil,
        distanceKm: Double? = nil
    ) async throws -> [Demand] {
        try await service.searchDemands(
            page: page,
            limit: limit,
            keyword: keyword,
            lat: lat,
            lng: lng,
            distanceKm: distanceKm
        )
    }

    func activePool(page: Int = 1, pageSize: Int = 20) async throws -> [Demand] {
        try await service.poolActive(page: page, pageSize: pageSize)
    }

    func closedPool(page: Int = 1, pageSize: Int = 20) async throws -> [Demand] {
        try await service.poolDead(page: page, pageSize: pageSize)
    }

    func detail(id: String) async throws -> Demand {
        try await service.getDemand(id: id)
    }

    func mine(page: Int = 1) async throws -> [Demand] {
        try await service.myDemands(page: page)
    }

    func listDrafts(page: Int = 1) async throws -> [Demand] {
        try await service.listDrafts(page: page)
    }

    @discardableResult
    func publishDraft(id: String) async throws -> Demand {
        let dto = try await service.publishDraft(id: id)
        return DemandMapper.mapDetail(dto)
    }

    func myApplications(page: Int = 1) async throws -> [Demand] {
        try await service.myApplications(page: page)
    }

    func applicants(demandID: String) async throws -> [DemandApplicant] {
        try await service.applicants(demandId: demandID)
    }

    func bids(demandID: String) async throws -> [DemandBidDTO] {
        try await service.bids(id: demandID)
    }

    func request(
        demandID: String,
        message: String,
        idempotencyKey: String
    ) async throws -> DemandApplicantDTO {
        try await service.requestApply(
            id: demandID,
            message: message,
            idempotencyKey: idempotencyKey
        )
    }

    func bid(demandID: String, offerPrice: Decimal?, message: String) async throws {
        try await service.bid(id: demandID, offerPrice: offerPrice, message: message)
    }

    func accept(
        demandID: String,
        applicantID: String,
        idempotencyKey: String
    ) async throws -> DemandAcceptResultDTO {
        try await service.acceptApplicant(
            demandId: demandID,
            applicantId: applicantID,
            idempotencyKey: idempotencyKey
        )
    }

    func reject(
        demandID: String,
        applicantID: String,
        idempotencyKey: String
    ) async throws {
        try await service.rejectApplicant(
            demandId: demandID,
            applicantId: applicantID,
            idempotencyKey: idempotencyKey
        )
    }

    func withdraw(id: String) async throws {
        try await service.withdraw(id: id)
    }

    func delete(id: String) async throws {
        try await service.deleteDemand(id: id)
    }

    func extendCommunication(
        demandID: String,
        applicantID: String,
        minutes: Int
    ) async throws -> DemandApplicantDTO {
        try await service.extendCommunication(
            demandID: demandID,
            applicantID: applicantID,
            minutes: minutes
        )
    }

    func takeImmediately(id: String) async throws {
        try await service.snatch(id: id)
    }
}
