import Foundation

struct AppUser: Identifiable, Hashable {
    let id: String
    var name: String
    var avatarUrl: String?
    var coverUrl: String?
    var demandCardCoverUrl: String?
    var creditScore: Int
    var completedOrders: Int
    var goodRate: Double

    var avatarMediaURL: URL? { APIConfig.mediaURL(avatarUrl) }
    var coverMediaURL: URL? { APIConfig.mediaURL(coverUrl) }
    var cardCoverMediaURL: URL? { APIConfig.mediaURL(demandCardCoverUrl) }

    static func from(_ user: SoftUserDTO?) -> AppUser {
        AppUser(
            id: user?.id ?? "unknown",
            name: user?.nickname ?? "用户",
            avatarUrl: user?.avatarUrl,
            coverUrl: user?.coverUrl,
            demandCardCoverUrl: user?.demandCardCoverUrl,
            creditScore: user?.creditScore ?? 60,
            completedOrders: user?.completedOrders ?? 0,
            goodRate: 0
        )
    }
}

struct Demand: Identifiable, Hashable {
    enum State: Hashable {
        case normal
        case urgent
        case full
    }

    let id: String
    var title: String
    var expectedOutcome: String
    var minPrice: Decimal
    var expectedPrice: Decimal?
    var distanceText: String
    var countdownText: String
    var applicantCount: Int
    var applicantLimit: Int
    var tags: [String]
    var state: State
    var publisher: AppUser
    var deadlineText: String
    var isCertifiedOnly: Bool
    var allowNearby: Bool
    var status: DemandStatus = .unknown("UNKNOWN")
    var visibleUntil: Date? = nil
    var isOwner: Bool = false
    var hasRequested: Bool = false
    var hasOrder: Bool = false
    var coverImageUrl: String?

    /// 列表预览用封面（仅需求自身图）。详情页不再重复展示装饰图。
    var listCoverMediaURL: URL? {
        guard let coverImageUrl else { return nil }
        return APIConfig.mediaURL(coverImageUrl)
    }

    /// 详情/其它场景：需求封面 → 发布者服务卡/主页图
    var coverMediaURL: URL? {
        if let coverImageUrl { return APIConfig.mediaURL(coverImageUrl) }
        return publisher.cardCoverMediaURL ?? publisher.coverMediaURL
    }

    /// 副标题与标题过近时不在列表重复展示
    var listSubtitle: String? {
        let outcome = expectedOutcome.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !outcome.isEmpty else { return nil }
        if outcome == t { return nil }
        if outcome.hasPrefix(t), outcome.count < t.count + 8 { return nil }
        return outcome
    }
}

enum DemandStatus: Hashable {
    case active
    case frozen
    case inProgress
    case completed
    case withdrawn
    case cancelled
    case unknown(String)

    init(rawValue: String?) {
        let raw = rawValue?.uppercased() ?? "UNKNOWN"
        switch raw {
        case "ACTIVE", "PENDING": self = .active
        case "FROZEN": self = .frozen
        case "IN_PROGRESS", "ACCEPTED": self = .inProgress
        case "COMPLETED": self = .completed
        case "WITHDRAWN": self = .withdrawn
        case "CANCELLED": self = .cancelled
        default: self = .unknown(raw)
        }
    }

    var title: String {
        switch self {
        case .active: "公开中"
        case .frozen: "已冻结"
        case .inProgress: "履约中"
        case .completed: "已完成"
        case .withdrawn: "已撤回"
        case .cancelled: "已取消"
        case .unknown: "状态更新中"
        }
    }

    var acceptsRequests: Bool { self == .active }
}

struct DemandApplicant: Identifiable, Hashable {
    let id: String
    let user: AppUser
    let message: String
    let status: String
    let createdAt: Date?
    let communicationDeadline: Date?

    var isActionable: Bool {
        ["PENDING", "COMMUNICATING"].contains(status.uppercased())
    }
}

struct Order: Identifiable, Hashable {
    enum Stage: Int, CaseIterable, Hashable {
        case accepted = 0
        case inProgress
        case waitingReview
        case completed
        case disputed

        var title: String {
            switch self {
            case .accepted: "已接单"
            case .inProgress: "进行中"
            case .waitingReview: "待验收"
            case .completed: "已完成"
            case .disputed: "争议"
            }
        }
    }

    let id: String
    var demand: Demand
    var provider: AppUser
    var requesterId: String?
    var providerId: String?
    var stage: Stage
    var rawStatus: String
    var paidAt: String?
    var completedAt: String?
    var submittedAtText: String
    var dealAmount: Decimal
    var escrowAmount: Decimal
    var remainingPay: Decimal
    var serviceFee: Decimal
    var amountHint: String

    /// 预付服务费后，验收时跳过服务费；未预付则验收时一并收取
    var totalDue: Decimal { paidAt == nil ? remainingPay + serviceFee : remainingPay }
    var isPrepaid: Bool { paidAt != nil }
}

struct ChatThread: Identifiable, Hashable {
    let id: String
    var peer: AppUser
    var preview: String
    var timeText: String
    var unreadCount: Int
    var relatedDemandTitle: String?
    var isCommunicating: Bool
    var isSystem: Bool
    var remainingCommText: String?
}

enum ChatBubbleKind: Hashable {
    case system(String)
    case time(String)
    case text(String, isMine: Bool)
    case demandCard
}

struct WalletEscrowItem: Identifiable, Hashable {
    let id: String
    var title: String
    var amount: Decimal
    var statusText: String
    var isFrozen: Bool
}

struct WalletTxn: Identifiable, Hashable {
    let id: String
    var title: String
    var timeText: String
    var amount: Decimal
    var isIncome: Bool
    var symbol: String
}

extension Decimal {
    var pointsText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let n = NSDecimalNumber(decimal: self)
        return "\(formatter.string(from: n) ?? n.stringValue) 点"
    }

    var moneyText: String { pointsText }
    var currencyText: String { pointsText }
}
