import Foundation

// MARK: - Envelope

struct APIEnvelope<T: Decodable>: Decodable {
    let code: Int
    let message: String
    let data: T?
    let timestamp: Int64?
    let requestId: String?
}

struct APIErrorEnvelope: Decodable {
    let code: Int?
    let error: String?
    let message: String?
    let timestamp: Int64?
    let requestId: String?
}

struct PaginatedItems<T: Decodable>: Decodable {
    let items: [T]
    let page: Int
    let limit: Int?
    let total: Int
    let totalPages: Int
}

/// 兼容服务端金额既可能是 JSON number 也可能是十进制字符串。
/// 资金字段解析失败必须暴露契约错误，不能伪装为真实的 0。
struct FlexibleDecimal: Decodable, Hashable {
    let value: Decimal

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let d = try? container.decode(Decimal.self) {
            value = d
        } else if let s = try? container.decode(String.self), let d = Decimal(string: s) {
            value = d
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "金额必须是有效的十进制数字或十进制字符串"
            )
        }
    }
}

struct SoftUserDTO: Decodable, Hashable, Identifiable {
    let id: String
    let phone: String?
    let nickname: String?
    let avatarUrl: String?
    let coverUrl: String?
    let demandCardCoverUrl: String?
    let creditScore: Int?
    let certificationLevel: String?
    let completedOrders: Int?
    let bio: String?
    let cityCode: String?
    let ipRegion: String?
    let isFollowing: Bool?

    var avatarMediaURL: URL? { APIConfig.mediaURL(avatarUrl) }
    var coverMediaURL: URL? { APIConfig.mediaURL(coverUrl) }
    var cardCoverMediaURL: URL? { APIConfig.mediaURL(demandCardCoverUrl) }
}

// MARK: - Auth

struct AuthPayloadDTO: Decodable {
    let token: String
    let user: UserDTO
}

struct UserDTO: Decodable, Hashable {
    let id: String
    let phone: String?
    let nickname: String?
    let avatarUrl: String?
    let coverUrl: String?
    let demandCardCoverUrl: String?
    let creditScore: Int?
    let certificationLevel: String?
    let completedOrders: Int?

    var avatarMediaURL: URL? { APIConfig.mediaURL(avatarUrl) }
    var coverMediaURL: URL? { APIConfig.mediaURL(coverUrl) }
}

// MARK: - Demand

struct DemandListItemDTO: Decodable {
    let id: String
    let title: String
    let description: String?
    let descriptionPreview: String?
    let expectedOutcome: String?
    let minPrice: FlexibleDecimal?
    let expectedPrice: FlexibleDecimal?
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
    let isCertifiedOnly: Bool?
    let tags: [String]?
    let user: SoftUserDTO?
    let coverImage: String?
    let coverUrl: String?
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
    let category: String?
    let tagName: String?
    let tags: [String]?
    let serviceType: String?
    let expireAt: String?
    let visibleUntil: String?
    let timeLimit: String?
    let applicantCount: Int?
    let maxApplicants: Int?
    let isCertifiedOnly: Bool?
    let status: String?
    let visibilityWindow: Int?
    let user: SoftUserDTO?
    let isOwner: Bool?
    let hasOrder: Bool?
    let acceptedProviderId: String?
    let applicantsV2: [DemandApplicantDTO]?
    let coverImage: String?
    let coverUrl: String?
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

// MARK: - Order

struct OrderListResult: Decodable {
    let orders: [OrderDTO]
    let total: Int
    let page: Int
    let totalPages: Int
}

struct OrderDTO: Decodable {
    let id: String
    let demandId: String?
    let status: String
    let agreedPrice: FlexibleDecimal?
    let paidAt: String?
    let completedAt: String?
    let createdAt: String?
    let provider: SoftUserDTO?
    let requester: SoftUserDTO?
    let demand: OrderDemandDTO?
}

struct OrderDemandDTO: Decodable {
    let id: String
    let title: String?
    let description: String?
    let minPrice: FlexibleDecimal?
    let category: String?
    let timeLimit: Int?
}

// MARK: - Message

struct ConversationDTO: Decodable {
    let user: SoftUserDTO
    let lastMessage: MessageDTO?
    let unreadCount: Int?
}

struct MessageDTO: Decodable {
    let id: String
    let fromUserId: String
    let toUserId: String
    let content: String
    let type: String?
    let isRead: Bool?
    let createdAt: String?
    let fromUser: SoftUserDTO?
    let toUser: SoftUserDTO?
}

struct SendMessageBody: Encodable {
    let toUserId: String
    let content: String
}

struct UnreadCountDTO: Decodable {
    let count: Int
}

// MARK: - Wallet

struct WalletSummaryDTO: Decodable {
    let balance: FlexibleDecimal
    let held: FlexibleDecimal
    let monthlyIncome: FlexibleDecimal?
    let monthlyExpense: FlexibleDecimal?
}

struct WalletLedgerItemDTO: Decodable, Identifiable {
    let id: String
    let type: String
    let amount: FlexibleDecimal
    let balanceAfter: FlexibleDecimal?
    let referenceType: String?
    let referenceId: String?
    let memo: String?
    let createdAt: String
}

struct WalletLedgerPageDTO: Decodable {
    let items: [WalletLedgerItemDTO]
    let total: Int
    let page: Int
    let totalPages: Int
}

// MARK: - Loop

indirect enum LoopJSONValue: Codable, Hashable, Sendable {
    case object([String: LoopJSONValue])
    case array([LoopJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([LoopJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: LoopJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "不支持的自然回 JSON 值"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct LoopOfferingItemDTO: Decodable, Identifiable {
    let id: String
    let title: String
    let summary: String?
    let loopKind: String
    let definitionCode: String?
    let definitionName: String?
    let definitionDescription: String?
    let paths: [String]?
    let requiresVerification: Bool?
}

struct LoopRecommendationResultDTO: Decodable {
    let query: String?
    let items: [LoopRecommendationDTO]
    let humanFallback: HumanFallbackDTO?
}

struct LoopRecommendationDTO: Decodable, Identifiable {
    let id: String
    let title: String
    let summary: String?
    let loopKind: String
    let definitionCode: String?
    let definitionName: String?
    let paths: [String]?
    let requiresVerification: Bool?
    let executionMode: String?
}

struct HumanFallbackDTO: Decodable {
    let kind: String?
    let title: String?
    let description: String?
    let paths: [String]?
    let requiresConfirmation: Bool?
}

struct LoopRunDetailDTO: Decodable {
    let id: String
    let loopKind: String
    let status: String
    let initiatorRef: String?
    let receiverRef: String?
    let inputJson: LoopJSONValue?
    let expectedOutcome: LoopJSONValue?
    let actualOutcome: LoopJSONValue?
    let demandId: String?
    let orderId: String?
    let parentRunId: String?
    let correlationId: String?
    let startedAt: String?
    let completedAt: String?
    let createdAt: String?
    let updatedAt: String?
    let definition: LoopDefinitionDTO?
    let offering: LoopOfferingBriefDTO?
    let events: [LoopEventDTO]?
    let verificationRuns: [LoopVerificationRunDTO]?
    let linksOut: [LoopLinkDTO]?
    let linksIn: [LoopLinkDTO]?
}

struct LoopDefinitionDTO: Decodable {
    let code: String?
    let name: String?
    let description: String?
    let loopKind: String?
    let executionMode: String?
    let inputSchema: LoopJSONValue?
    let outcomeSchema: LoopJSONValue?
}

struct LoopOfferingBriefDTO: Decodable {
    let id: String
    let title: String?
    let summary: String?
}

struct LoopEventDTO: Decodable {
    let id: String?
    let type: String
    let actorRef: String?
    let visibility: String?
    let payload: LoopJSONValue?
    let createdAt: String?
}

struct LoopVerifierDTO: Decodable, Identifiable {
    let id: String
    let code: String
    let name: String
}

struct LoopVerificationRunDTO: Decodable, Identifiable {
    let id: String
    let status: String
    let resultJson: LoopJSONValue?
    let createdAt: String?
    let verifier: LoopVerifierDTO?
}

struct LoopLinkedRunDTO: Decodable, Identifiable {
    let id: String
    let status: String
    let definition: LoopDefinitionDTO?
}

struct LoopLinkDTO: Decodable, Identifiable {
    let id: String
    let relation: String
    let meta: LoopJSONValue?
    let createdAt: String?
    let targetRun: LoopLinkedRunDTO?
    let sourceRun: LoopLinkedRunDTO?
}

struct MyLoopsResultDTO: Decodable {
    let items: [MyLoopItemDTO]
    let summary: MyLoopSummaryDTO?
}

struct MyLoopItemDTO: Decodable, Identifiable {
    let id: String
    let kind: String
    let status: String
    let progress: Double?
    let demandId: String?
    let orderId: String?
    let initiatorRef: String?
    let receiverRef: String?
    let startedAt: String?
    let completedAt: String?
    let createdAt: String?
    let eventCount: Int?
    let latestEvent: LoopEventDTO?
    let definition: LoopDefinitionDTO?
    let offering: LoopOfferingBriefDTO?
}

struct MyLoopSummaryDTO: Decodable {
    let total: Int?
    let active: Int?
    let succeeded: Int?
    let failed: Int?
    let successRate: Double?
}

struct HeavenCapabilityDTO: Decodable, Identifiable {
    let id: String
    let title: String
    let summary: String?
    let definitionCode: String?
    let status: String?
    let runCount: Int?
    let successCount: Int?
    let failCount: Int?
    let lastRunAt: String?
}

struct LoopRunOfferingResultDTO: Decodable {
    let runId: String?
    let ran: Bool?
    let preview: Bool?
    let code: String?
    let status: String?
    let outcome: LoopJSONValue?
}

struct LoopRetryVerificationResultDTO: Decodable {
    let runId: String
    let status: String
    let verification: String
}

// MARK: - Service Card / Misc

struct ServiceCardDTO: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String?
    let description: String?
    let category: String?
    let serviceType: String?
    let status: String?
    let tags: [String]?
    let priceMin: FlexibleDecimal?
    let priceMax: FlexibleDecimal?
    let publisher: SoftUserDTO?
}

struct CaptchaSiteKeyDTO: Decodable {
    let siteKey: String?
}

struct RegionDTO: Decodable, Identifiable {
    let id: Int
    let name: String?
    let parentId: Int?
}

struct TagDTO: Decodable, Hashable {
    let name: String
    let category: String?
}

struct CertStatusDTO: Decodable {
    let certificationLevel: String?
    let completedOrders: Int?
    let snatchCredits: Int?
    let creditScore: Int?

    enum CodingKeys: String, CodingKey {
        case certificationLevel, completedOrders, snatchCredits, creditScore
    }
}

struct CircleDTO: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    let memberCount: Int?
    let cityCode: String?
    let isMember: Bool?
    let role: String?
    let coverUrl: String?
    let inviteCode: String?
    let type: String?
    let ownerId: String?
    let owner: SoftUserDTO?

    var coverMediaURL: URL? { APIConfig.mediaURL(coverUrl) }

    enum CodingKeys: String, CodingKey {
        case id, name, description, memberCount, cityCode, isMember, role
        case coverUrl, inviteCode, type, ownerId, owner
        case count = "_count"
    }

    private enum CountKeys: String, CodingKey { case members }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        cityCode = try c.decodeIfPresent(String.self, forKey: .cityCode)
        isMember = try c.decodeIfPresent(Bool.self, forKey: .isMember)
        role = try c.decodeIfPresent(String.self, forKey: .role)
        coverUrl = try c.decodeIfPresent(String.self, forKey: .coverUrl)
        inviteCode = try c.decodeIfPresent(String.self, forKey: .inviteCode)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        ownerId = try c.decodeIfPresent(String.self, forKey: .ownerId)
        owner = try c.decodeIfPresent(SoftUserDTO.self, forKey: .owner)
        if let mc = try c.decodeIfPresent(Int.self, forKey: .memberCount) {
            memberCount = mc
        } else if let nested = try? c.nestedContainer(keyedBy: CountKeys.self, forKey: .count) {
            memberCount = try nested.decodeIfPresent(Int.self, forKey: .members)
        } else {
            memberCount = nil
        }
    }

    init(
        id: String,
        name: String,
        description: String?,
        memberCount: Int?,
        cityCode: String?,
        isMember: Bool?,
        role: String?,
        coverUrl: String?,
        inviteCode: String?,
        type: String?,
        ownerId: String?,
        owner: SoftUserDTO? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.memberCount = memberCount
        self.cityCode = cityCode
        self.isMember = isMember
        self.role = role
        self.coverUrl = coverUrl
        self.inviteCode = inviteCode
        self.type = type
        self.ownerId = ownerId
        self.owner = owner
    }
}

struct CirclesListResult: Decodable {
    let circles: [CircleDTO]
    let total: Int?
    let page: Int?
    let totalPages: Int?
}

struct CircleMembershipDTO: Decodable {
    let circleId: String?
    let role: String?
    let circle: CircleDTO?
}

struct CircleMemberDTO: Decodable, Identifiable, Hashable {
    var id: String { userId }
    let userId: String
    let role: String?
    let joinedAt: String?
    let lastActiveLabel: String?
    let user: SoftUserDTO?
}

struct CircleMembersPage: Decodable {
    let items: [CircleMemberDTO]
    let total: Int?
    let page: Int?
}

struct CircleResourceDTO: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    let fileUrl: String?
    let mimeType: String?
    let sizeLabel: String?
    let category: String?
    let createdAt: String?
    let uploader: SoftUserDTO?
}

struct CircleResourcesPage: Decodable {
    let items: [CircleResourceDTO]?
    let recent: [CircleResourceDTO]?
    let total: Int?
}

struct CircleActivityDTO: Decodable, Identifiable, Hashable {
    let id: String
    let type: String?
    let title: String?
    let summary: String?
    let createdAt: String?
    let actor: SoftUserDTO?
}

struct CircleActivitiesPage: Decodable {
    let items: [CircleActivityDTO]
    let total: Int?
    let page: Int?
}

struct CircleHubHomeDTO: Decodable {
    let stats: CircleHubStatsDTO?
    let announcement: CircleAnnouncementDTO?
}

struct CircleHubStatsDTO: Decodable {
    let todayActive: Int?
    let newDemands: Int?
    let weekDemands: Int?
    let resourceUpdates: Int?
    let memberCount: Int?
    let pendingInvites: Int?
}

struct CircleAnnouncementDTO: Decodable {
    let title: String?
    let body: String?
    let pinned: Bool?
}

struct DemandBidDTO: Decodable {
    let id: String?
    let offerPrice: FlexibleDecimal?
    let message: String?
    let status: String?
    let createdAt: String?
    let user: SoftUserDTO?
}
