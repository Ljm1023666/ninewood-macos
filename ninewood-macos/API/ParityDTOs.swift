import Foundation

// MARK: - Extra DTOs for Windows parity

struct UserListPage: Decodable {
    let items: [SoftUserDTO]?
    let users: [SoftUserDTO]?
    let total: Int?
    let page: Int?

    var rows: [SoftUserDTO] { items ?? users ?? [] }
}

struct NotificationDTO: Decodable, Identifiable, Hashable {
    let id: String
    let type: String?
    let title: String?
    let content: String?
    let isRead: Bool?
    let createdAt: String?
    let refId: String?
}

struct NotificationsPage: Decodable {
    let items: [NotificationDTO]?
    let notifications: [NotificationDTO]?
    var rows: [NotificationDTO] { items ?? notifications ?? [] }
}

struct MergeChatDTO: Decodable, Identifiable, Hashable {
    let id: String
    let title: String?
    let memberCount: Int?
    let updatedAt: String?
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
    let credits: Int?
    let snatchCredits: Int?
}
