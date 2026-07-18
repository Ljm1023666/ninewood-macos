import Foundation

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
    /// 公开资料字段（getPublicProfile）
    let serviceTags: [String]?
    /// 认证服务者列表兼容字段（providers 返回 `tags`）
    let tags: [String]?
    /// 认证服务者评分（`/certification/providers` 返回）
    let avgRating: Double?
    let totalCompleted: Int?

    init(
        id: String,
        phone: String? = nil,
        nickname: String? = nil,
        avatarUrl: String? = nil,
        coverUrl: String? = nil,
        demandCardCoverUrl: String? = nil,
        creditScore: Int? = nil,
        certificationLevel: String? = nil,
        completedOrders: Int? = nil,
        bio: String? = nil,
        cityCode: String? = nil,
        ipRegion: String? = nil,
        isFollowing: Bool? = nil,
        serviceTags: [String]? = nil,
        tags: [String]? = nil,
        avgRating: Double? = nil,
        totalCompleted: Int? = nil
    ) {
        self.id = id
        self.phone = phone
        self.nickname = nickname
        self.avatarUrl = avatarUrl
        self.coverUrl = coverUrl
        self.demandCardCoverUrl = demandCardCoverUrl
        self.creditScore = creditScore
        self.certificationLevel = certificationLevel
        self.completedOrders = completedOrders
        self.bio = bio
        self.cityCode = cityCode
        self.ipRegion = ipRegion
        self.isFollowing = isFollowing
        self.serviceTags = serviceTags
        self.tags = tags
        self.avgRating = avgRating
        self.totalCompleted = totalCompleted
    }

    var avatarMediaURL: URL? { APIConfig.mediaURL(avatarUrl) }
    var coverMediaURL: URL? { APIConfig.mediaURL(coverUrl) }
    var cardCoverMediaURL: URL? { APIConfig.mediaURL(demandCardCoverUrl) }

    /// 服务标签：优先 serviceTags，其次 tags
    var resolvedServiceTags: [String] {
        if let serviceTags, !serviceTags.isEmpty { return serviceTags }
        if let tags, !tags.isEmpty { return tags }
        return []
    }

    /// 展示用评分文案（无评分时为 nil，由 UI 决定占位）
    var displayRating: String? {
        guard let avgRating else { return nil }
        return String(format: "%.1f", avgRating)
    }
}

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
