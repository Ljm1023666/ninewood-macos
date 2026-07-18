import Foundation

struct ConversationDTO: Decodable {
    let user: SoftUserDTO
    let lastMessage: MessageDTO?
    let unreadCount: Int?
    let communication: CommunicationContextDTO?
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
    let orderId: String?
    let mergeId: String?
    let cardAttachment: CardAttachmentDTO?
}

struct CommunicationContextDTO: Decodable {
    let applicantId: String
    let demandId: String
    let demandTitle: String
    let status: String?
    let commStartAt: String?
    let commDeadline: String?
    let extensionMinutes: Int?
    let canExtend: Bool?
}

struct CardAttachmentDTO: Decodable {
    let id: String
    let cardType: String
    let demandId: String?
    let serviceCardId: String?
    let snapshot: CardSnapshotDTO?
}

struct CardSnapshotDTO: Decodable {
    let cardType: String?
    let cardId: String?
    let title: String?
    let description: String?
    let summary: String?
    let minPrice: FlexibleDecimal?
    let priceMin: FlexibleDecimal?
    let status: String?
    let coverImage: String?
    let coverUrl: String?
}

struct SendMessageBody: Encodable {
    let toUserId: String
    let content: String
}

struct UnreadCountDTO: Decodable {
    let count: Int
}

struct NotificationDTO: Decodable, Identifiable, Hashable {
    let id: String
    let type: String?
    let title: String?
    let content: String?
    let isRead: Bool?
    let createdAt: String?
    let refId: String?
    let orderId: String?
    let demandId: String?
    let path: String?

    var deepLink: NotificationDeepLink {
        NotificationDeepLink.resolve(from: self)
    }
}

struct NotificationsPage: Decodable {
    let items: [NotificationDTO]?
    let notifications: [NotificationDTO]?
    let total: Int?
    let page: Int?
    let totalPages: Int?
    var rows: [NotificationDTO] { items ?? notifications ?? [] }
}

enum NotificationDeepLink: Equatable, Sendable {
    case order(id: String)
    case demand(id: String)
    case path(String)
    case none

    static func resolve(from item: NotificationDTO) -> NotificationDeepLink {
        if let path = normalizedPath(item.path) {
            return .path(path)
        }
        if let orderId = nonEmpty(item.orderId) {
            return .order(id: orderId)
        }
        if let demandId = nonEmpty(item.demandId) {
            return .demand(id: demandId)
        }

        let type = (item.type ?? "").lowercased()
        if let ref = nonEmpty(item.refId) {
            if type.contains("order") { return .order(id: ref) }
            if type.contains("demand") { return .demand(id: ref) }
        }

        let haystack = [item.title, item.content, item.type]
            .compactMap { $0 }
            .joined(separator: " ")

        if let path = firstMatch(in: haystack, pattern: #"(/[a-zA-Z][\w\-/]*)"#),
           path.hasPrefix("/orders/") || path.hasPrefix("/demands/") || path.hasPrefix("/messages")
            || path.hasPrefix("/agent") || path.hasPrefix("/my-demands") || path.hasPrefix("/discover")
            || path.hasPrefix("/welfare") || path.hasPrefix("/circles") {
            return .path(path)
        }

        if let orderId = firstUUID(afterKeywords: ["订单", "order"], in: haystack) {
            return .order(id: orderId)
        }
        if let demandId = firstUUID(afterKeywords: ["需求", "demand"], in: haystack) {
            return .demand(id: demandId)
        }

        return .none
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedPath(_ raw: String?) -> String? {
        guard let raw = nonEmpty(raw), raw.hasPrefix("/") else { return nil }
        let withoutQuery = raw.split(separator: "?", maxSplits: 1).first.map(String.init) ?? raw
        return withoutQuery.hasSuffix("/") && withoutQuery.count > 1
            ? String(withoutQuery.dropLast())
            : withoutQuery
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[swiftRange])
    }

    private static func firstUUID(afterKeywords keywords: [String], in text: String) -> String? {
        let uuidPattern = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
        for keyword in keywords {
            let pattern = "\(NSRegularExpression.escapedPattern(for: keyword)).{0,24}(\(uuidPattern))"
            if let id = firstMatch(in: text, pattern: pattern) {
                return id
            }
        }
        return nil
    }
}
