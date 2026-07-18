import Foundation

struct DemandListItemDTO: Decodable {
    let id: String
    let title: String
    let description: String?
    let descriptionPreview: String?
    let expectedOutcome: String?
    let minPrice: FlexibleDecimal?
    let expectedPrice: FlexibleDecimal?
    let amountEstimate: FlexibleDecimal?
    let deposit: FlexibleDecimal?
    let applicantCount: Int?
    let maxApplicants: Int?
    let tagName: String?
    let category: String?
    let serviceType: String?
    let deadlineAt: String?
    let expireAt: String?
    let createdAt: String?
    let distance: Double?
    let distanceKm: Double?
    let status: String?
    let lifecycleStage: String?
    let isCertifiedOnly: Bool?
    let tags: [String]?
    let user: SoftUserDTO?
    let coverImage: String?
    let coverUrl: String?
    let mediaUrls: FlexibleStringList?
}

struct DemandsSearchResult: Decodable {
    let demands: [DemandListItemDTO]
    let total: Int
    let page: Int
    let limit: Int
    let totalPages: Int
}

struct DemandDetailDTO: Decodable {
    let id: String
    let title: String
    let description: String?
    let expectedOutcome: String?
    let minPrice: FlexibleDecimal?
    let amountEstimate: FlexibleDecimal?
    let deposit: FlexibleDecimal?
    let category: String?
    let tagName: String?
    let tags: [String]?
    let serviceType: String?
    let expireAt: String?
    let visibleUntil: String?
    let timeLimit: FlexibleDateValue?
    let applicantCount: Int?
    let maxApplicants: Int?
    let isCertifiedOnly: Bool?
    let status: String?
    let lifecycleStage: String?
    let visibilityWindow: Int?
    let user: SoftUserDTO?
    let isOwner: Bool?
    let hasOrder: Bool?
    let acceptedProviderId: String?
    let applicantsV2: [DemandApplicantDTO]?
    let coverImage: String?
    let coverUrl: String?
    let mediaUrls: FlexibleStringList?
    /// 创建成功响应 BR-001 资金字段（详情 GET 也可能带回）
    let currency: String?
    let ruleVersion: String?
    let depositRequired: FlexibleDecimal?
    let escrowRequired: FlexibleDecimal?
    let serviceFeeRate: Double?
    let payableNow: FlexibleDecimal?
}

struct DemandApplicantDTO: Decodable {
    let id: String
    let demandId: String?
    let userId: String
    let message: String?
    let status: String
    let createdAt: String?
    let commStartAt: String?
    let commDeadline: String?
    let user: SoftUserDTO?
}

struct DemandAcceptResultDTO: Decodable {
    let ok: Bool?
    let acceptedUserId: String?
    let orderId: String?
}

struct OperationResultDTO: Decodable {
    let ok: Bool?
    let message: String?
}

struct DemandRequestBody: Encodable {
    let message: String
}

struct DemandApplyBody: Encodable {
    let offerPrice: Double?
    let message: String?
}

struct DemandBidDTO: Decodable {
    let id: String?
    let offerPrice: FlexibleDecimal?
    let message: String?
    let status: String?
    let createdAt: String?
    let user: SoftUserDTO?
}
