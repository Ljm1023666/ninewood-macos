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

    init(_ value: Decimal) {
        self.value = value
    }

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

/// 兼容 ISO 时间字符串与历史 int（分钟/时间戳）；解码失败时记为 nil，不拖垮整单。
struct FlexibleDateValue: Decodable, Hashable {
    let isoString: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            isoString = nil
            return
        }
        if let s = try? container.decode(String.self) {
            isoString = s
            return
        }
        // 历史契约偶发传 Int 分钟或时间戳：忽略数值，避免整单解码失败
        if (try? container.decode(Int.self)) != nil || (try? container.decode(Double.self)) != nil {
            isoString = nil
            return
        }
        isoString = nil
    }
}

/// 兼容 `mediaUrls` 为字符串数组或 JSON 字符串。
struct FlexibleStringList: Decodable, Hashable {
    let values: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            values = []
            return
        }
        if let arr = try? container.decode([String].self) {
            values = arr
            return
        }
        if let s = try? container.decode(String.self) {
            if s.isEmpty {
                values = []
                return
            }
            if let data = s.data(using: .utf8),
               let arr = try? JSONDecoder().decode([String].self, from: data) {
                values = arr
                return
            }
            values = [s]
            return
        }
        values = []
    }
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
    /// 可选：服务端若返回则可展示「基数 × 费率」公式。
    let feeRate: Double?
    let baseAmount: FlexibleDecimal?
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

struct LoopOfferingMetricsDTO: Decodable, Sendable {
    let dealRate: Double?
    let avgDurationMs: Double?
    let publicSuccessRate: Double?
    let sampleSize: Int?
    let successRateStatus: String?
}

struct LoopVerificationSummaryDTO: Decodable, Sendable {
    let status: String?
    let verifierCount: Int?
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
    let metrics: LoopOfferingMetricsDTO?
    let verification: LoopVerificationSummaryDTO?
    let inputSchema: LoopJSONValue?
    let outcomeSchema: LoopJSONValue?
}

struct LoopResolvedQueryDTO: Decodable, Sendable {
    let paths: [String]?
    let facets: [String]?
    let suggestions: [String]?
    let status: String?
}

struct LoopMatchDTO: Decodable, Sendable {
    let matchedPaths: [String]?
    let textMatched: Bool?
    let reasons: [String]?
}

struct LoopRecommendationResultDTO: Decodable {
    let query: String?
    let resolved: LoopResolvedQueryDTO?
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
    let definitionDescription: String?
    let paths: [String]?
    let requiresVerification: Bool?
    let executionMode: String?
    let metrics: LoopOfferingMetricsDTO?
    let verification: LoopVerificationSummaryDTO?
    let match: LoopMatchDTO?
}

struct HumanFallbackDTO: Decodable {
    let kind: String?
    let title: String?
    let description: String?
    let paths: [String]?
    let facets: [String]?
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

struct MyLoopKindSummaryDTO: Decodable, Sendable {
    let total: Int?
    let active: Int?
    let succeeded: Int?
    let successRate: Double?
}

struct MyLoopSummaryDTO: Decodable {
    let total: Int?
    let active: Int?
    let succeeded: Int?
    let failed: Int?
    let successRate: Double?
    let byKind: [String: MyLoopKindSummaryDTO]?
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

    enum CodingKeys: String, CodingKey {
        case id, title, summary, description, category, serviceType, status, tags
        case priceMin, priceMax, publisher, user
    }

    init(
        id: String,
        title: String,
        summary: String? = nil,
        description: String? = nil,
        category: String? = nil,
        serviceType: String? = nil,
        status: String? = nil,
        tags: [String]? = nil,
        priceMin: FlexibleDecimal? = nil,
        priceMax: FlexibleDecimal? = nil,
        publisher: SoftUserDTO? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.description = description
        self.category = category
        self.serviceType = serviceType
        self.status = status
        self.tags = tags
        self.priceMin = priceMin
        self.priceMax = priceMax
        self.publisher = publisher
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        serviceType = try c.decodeIfPresent(String.self, forKey: .serviceType)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        tags = try c.decodeIfPresent([String].self, forKey: .tags)
        priceMin = try c.decodeIfPresent(FlexibleDecimal.self, forKey: .priceMin)
        priceMax = try c.decodeIfPresent(FlexibleDecimal.self, forKey: .priceMax)
        if let publisher = try c.decodeIfPresent(SoftUserDTO.self, forKey: .publisher) {
            self.publisher = publisher
        } else {
            self.publisher = try c.decodeIfPresent(SoftUserDTO.self, forKey: .user)
        }
    }
}

struct CaptchaSiteKeyDTO: Decodable {
    let siteKey: String?
    /// `hcaptcha` | `bypass`（未配置人机验证时）
    let mode: String?
}

struct CaptchaVerifyDTO: Decodable {
    let success: Bool
    let token: String
    let message: String?
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

struct CircleLastActivityDTO: Decodable, Hashable {
    let at: String?
    let label: String?
    let type: String?
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
    let memberCapacity: Int?
    let lastActivity: CircleLastActivityDTO?

    var coverMediaURL: URL? { APIConfig.mediaURL(coverUrl) }

    enum CodingKeys: String, CodingKey {
        case id, name, description, memberCount, cityCode, isMember, role
        case coverUrl, inviteCode, type, ownerId, owner, memberCapacity, lastActivity
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
        memberCapacity = try c.decodeIfPresent(Int.self, forKey: .memberCapacity)
        lastActivity = try c.decodeIfPresent(CircleLastActivityDTO.self, forKey: .lastActivity)
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
        owner: SoftUserDTO? = nil,
        memberCapacity: Int? = nil,
        lastActivity: CircleLastActivityDTO? = nil
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
        self.memberCapacity = memberCapacity
        self.lastActivity = lastActivity
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
    let purpose: String?
    let memberCapacity: Int?
    let activeMembers: CircleActiveMembersDTO?
    let heartbeat: CircleHeartbeatDTO?
    let recentResources: [CircleResourceDTO]?
    let activities: [CircleActivityDTO]?

    init(
        stats: CircleHubStatsDTO? = nil,
        announcement: CircleAnnouncementDTO? = nil,
        purpose: String? = nil,
        memberCapacity: Int? = nil,
        activeMembers: CircleActiveMembersDTO? = nil,
        heartbeat: CircleHeartbeatDTO? = nil,
        recentResources: [CircleResourceDTO]? = nil,
        activities: [CircleActivityDTO]? = nil
    ) {
        self.stats = stats
        self.announcement = announcement
        self.purpose = purpose
        self.memberCapacity = memberCapacity
        self.activeMembers = activeMembers
        self.heartbeat = heartbeat
        self.recentResources = recentResources
        self.activities = activities
    }
}

struct CircleActiveMembersDTO: Decodable {
    let items: [CircleActiveMemberItemDTO]?
    let extraCount: Int?
    let total: Int?
}

struct CircleActiveMemberItemDTO: Decodable, Identifiable, Hashable {
    var id: String { userId }
    let userId: String
    let nickname: String?
    let avatarUrl: String?

    var avatarMediaURL: URL? { APIConfig.mediaURL(avatarUrl) }
}

struct CircleHeartbeatDTO: Decodable {
    let label: String?
    let speakers7d: Int?
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
    let createdAt: String?
}

struct CircleInviteCodeDTO: Decodable {
    let inviteCode: String?
}
