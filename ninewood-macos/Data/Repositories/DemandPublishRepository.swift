import Foundation

struct DemandPublishMetadata {
    let tags: [TagDTO]
    let regions: [RegionDTO]
}

/// 发布需求用例边界：组合元数据读取与需求创建，避免 View 直接协调多个 API Service。
@MainActor
final class DemandPublishRepository {
    private let demands: DemandService
    private let tags: TagService
    private let regions: RegionService

    init(demands: DemandService, tags: TagService, regions: RegionService) {
        self.demands = demands
        self.tags = tags
        self.regions = regions
    }

    func loadMetadata() async -> DemandPublishMetadata {
        async let availableTags = tags.list()
        async let availableRegions = regions.children()
        return await DemandPublishMetadata(
            tags: (try? availableTags) ?? [],
            regions: (try? availableRegions) ?? []
        )
    }

    func publish(
        _ command: DemandPublishCommand,
        files: [MultipartFile],
        idempotencyKey: String
    ) async throws {
        _ = try await demands.createDemand(
            title: command.title,
            description: command.expectedOutcome,
            expectedOutcome: command.expectedOutcome,
            minPrice: command.minimumPrice,
            expectedPrice: command.expectedPrice,
            category: command.category,
            serviceType: command.serviceType,
            maxApplicants: command.maximumApplicants,
            isCertifiedOnly: command.certifiedProvidersOnly,
            tags: command.tags,
            regionId: command.regionID,
            timeLimitMinutes: command.timeLimitMinutes,
            files: files,
            idempotencyKey: idempotencyKey
        )
    }

    func saveDraft(_ command: DemandPublishCommand) async throws {
        _ = try await demands.saveDraft(
            title: command.title,
            description: command.expectedOutcome,
            expectedOutcome: command.expectedOutcome,
            minPrice: command.minimumPrice,
            expectedPrice: command.expectedPrice,
            category: command.category,
            serviceType: command.serviceType,
            maxApplicants: command.maximumApplicants,
            isCertifiedOnly: command.certifiedProvidersOnly,
            tags: command.tags,
            regionId: command.regionID,
            timeLimitMinutes: command.timeLimitMinutes
        )
    }
}
