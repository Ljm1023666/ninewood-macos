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
    var deposit: Decimal? = nil
    var mediaUrls: [String] = []
    var lifecycleStage: String? = nil
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
    /// 我的应标列表中对应的申请 ID（用于撤回）
    var applicationId: String? = nil

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
        case cancelled

        var title: String {
            switch self {
            case .accepted: "已接单"
            case .inProgress: "进行中"
            case .waitingReview: "待验收"
            case .completed: "已完成"
            case .disputed: "争议"
            case .cancelled: "已取消"
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
    /// 为 false 时，服务费等分项尚未经服务端资金字段确认，不得用于付款确认文案。
    var amountsFromServer: Bool = false

    /// 预付服务费后，验收时跳过服务费；未预付则验收时一并收取
    var totalDue: Decimal { paidAt == nil ? remainingPay + serviceFee : remainingPay }
    var isPrepaid: Bool { paidAt != nil }

    var escrowDisplayText: String {
        amountsFromServer ? escrowAmount.currencyText : "—"
    }

    var remainingPayDisplayText: String {
        amountsFromServer ? remainingPay.currencyText : "—"
    }

    var serviceFeeDisplayText: String {
        if serviceFee > 0 { return serviceFee.currencyText }
        return amountsFromServer ? "打开预付查看服务端分项" : "—"
    }
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
    var communication: CommunicationContext? = nil
}

struct CommunicationContext: Hashable {
    let applicantID: String
    let demandID: String
    let demandTitle: String
    let deadline: Date?
    let canExtend: Bool
    let extensionMinutes: Int

    func remainingText(at date: Date = Date()) -> String {
        guard let deadline else { return "沟通中" }
        let seconds = deadline.timeIntervalSince(date)
        guard seconds > 0 else { return "沟通窗口已到期" }
        let minutes = max(1, Int(ceil(seconds / 60)))
        return "剩余约 \(minutes) 分钟"
    }
}

struct ChatCardAttachment: Hashable {
    enum Kind: String, Hashable {
        case demand = "DEMAND"
        case serviceCard = "SERVICE_CARD"
        case unknown
    }

    let id: String
    let kind: Kind
    let cardID: String?
    let title: String
    let summary: String?
    let price: Decimal?
    let status: String?
    let coverImage: String?
    let isMine: Bool
}

struct ChatBubbleSender: Hashable {
    let userId: String
    let name: String
    let avatarURL: URL?
}

enum ChatBubbleKind: Hashable {
    case system(String)
    case time(String)
    case text(String, isMine: Bool, sender: ChatBubbleSender?)
    case card(ChatCardAttachment, sender: ChatBubbleSender?)
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
