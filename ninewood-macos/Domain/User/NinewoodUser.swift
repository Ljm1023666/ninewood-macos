import Foundation

/// 客户端统一用户模型；API 的完整/精简响应只影响可选字段，不再产生三套用户语义。
struct NinewoodUser: Identifiable, Hashable, Sendable {
    let id: String
    var phone: String?
    var nickname: String
    var avatarURL: URL?
    var coverURL: URL?
    var biography: String?
    var creditScore: Int
    var certificationLevel: String?
    var completedOrders: Int
    var region: String?
    var isFollowing: Bool?

    init(_ dto: UserDTO) {
        id = dto.id
        phone = dto.phone
        nickname = dto.nickname ?? "九木用户"
        avatarURL = dto.avatarMediaURL
        coverURL = dto.coverMediaURL
        biography = nil
        creditScore = dto.creditScore ?? 60
        certificationLevel = dto.certificationLevel
        completedOrders = dto.completedOrders ?? 0
        region = nil
        isFollowing = nil
    }

    init(_ dto: SoftUserDTO) {
        id = dto.id
        phone = dto.phone
        nickname = dto.nickname ?? "用户"
        avatarURL = dto.avatarMediaURL
        coverURL = dto.coverMediaURL
        biography = dto.bio
        creditScore = dto.creditScore ?? 60
        certificationLevel = dto.certificationLevel
        completedOrders = dto.completedOrders ?? 0
        region = dto.ipRegion ?? dto.cityCode
        isFollowing = dto.isFollowing
    }
}
