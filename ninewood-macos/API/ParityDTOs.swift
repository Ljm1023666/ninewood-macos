import Foundation

// MARK: - Extra DTOs for Windows parity

struct UserListPage: Decodable {
    let items: [SoftUserDTO]?
    let users: [SoftUserDTO]?
    let total: Int?
    let page: Int?

    var rows: [SoftUserDTO] { items ?? users ?? [] }
}

struct MergeChatMemberDTO: Decodable, Hashable {
    let id: String?
    let userId: String
    let mergeId: String?
    let createdAt: String?
}

struct MergeChatDTO: Decodable, Identifiable, Hashable {
    let id: String
    let title: String?
    let userId: String?
    let members: [MergeChatMemberDTO]?
    let createdAt: String?
    let updatedAt: String?

    var memberCount: Int { members?.count ?? 0 }
    var displayTitle: String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "群聊" : trimmed
    }
}

struct WelfareItemDTO: Decodable, Identifiable, Hashable {
    let id: String
    let title: String?
    let description: String?
    let status: String?
    let rewardPoints: FlexibleDecimal?
}

struct WelfareListPage: Decodable {
    let items: [WelfareItemDTO]?
    let demands: [WelfareItemDTO]?
    var rows: [WelfareItemDTO] { items ?? demands ?? [] }
}

struct CircleAnalyticsDTO: Decodable {
    let range: CircleAnalyticsRangeDTO?
    let kpis: CircleAnalyticsKPIsDTO?

    var rangeLabel: String? {
        guard let range else { return nil }
        if let start = range.start, let end = range.end {
            return "\(start) ~ \(end)"
        }
        return range.start ?? range.end
    }
}

struct CircleAnalyticsRangeDTO: Decodable {
    let start: String?
    let end: String?
}

struct CircleAnalyticsKPIsDTO: Decodable {
    let memberCount: Int?
    let memberGrowthPct: Double?
    let activeRate: Double?
    let activeRateDelta: Double?
    let weekDemands: Int?
    let weekDemandsDelta: Int?
    let interactions: Int?
    let interactionsDelta: Int?
}

struct ServiceCardInputBody: Encodable {
    let title: String
    let summary: String?
    let description: String
    let category: String
    let serviceType: String
    let tags: [String]?
    let priceMin: Double?
    let priceMax: Double?
    let deliveryMode: String?
    let availability: String?
}

struct BusyStatusDTO: Decodable {
    let isBusy: Bool?
    let allowSpecialSearch: Bool?
}

struct SnatchStatusDTO: Decodable {
    let certificationLevel: String?
    let snatchCredits: Int?
    /// 兼容旧字段名
    let credits: Int?

    var availableCredits: Int { snatchCredits ?? credits ?? 0 }
}

struct PushPreferenceDTO: Codable {
    var receivePushes: Bool?
    var pushFrequency: String?
    var excludeKeywords: [String]?
    var excludeTags: [String]?
    var excludeRegions: [Int]?
}
