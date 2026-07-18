import Foundation

struct WelfareRewardDTO: Decodable, Identifiable, Hashable {
    let id: String
    let demandId: String?
    let providerId: String?
    let amount: FlexibleDecimal?
    let isSpiritual: Bool?
    let rewardType: String?
    let choiceLabel: String?
    let badge: String?
    let createdAt: String?

    var displayTitle: String {
        if let choiceLabel, !choiceLabel.isEmpty { return choiceLabel }
        if let badge, !badge.isEmpty { return badge }
        if isSpiritual == true { return "精神激励" }
        return "福利奖励"
    }

    var isSpiritualReward: Bool { isSpiritual == true }
}

struct WelfareRewardsPage: Decodable {
    let items: [WelfareRewardDTO]?
    let total: Int?
    let page: Int?
    let totalPages: Int?
    let totalEarned: FlexibleDecimal?
    let badges: [String]?

    var rows: [WelfareRewardDTO] { items ?? [] }
}
