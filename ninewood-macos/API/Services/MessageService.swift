import Foundation

@MainActor
final class MessageService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func conversations() async throws -> [ChatThread] {
        let list: [ConversationDTO] = try await client.get("/messages/conversations")
        return list.map(MessageMapper.mapThread)
    }

    func messages(with userId: String, myUserId: String, page: Int = 1) async throws -> [ChatBubbleKind] {
        let list: [MessageDTO] = try await client.get(
            "/messages/\(userId)",
            query: [URLQueryItem(name: "page", value: String(page))]
        )
        return list.map { MessageMapper.mapBubble($0, myUserId: myUserId) }
    }

    func send(toUserId: String, content: String) async throws -> MessageDTO {
        try await client.post("/messages/send", body: SendMessageBody(toUserId: toUserId, content: content))
    }

    func unreadCount() async throws -> Int {
        let dto: UnreadCountDTO = try await client.get("/messages/unread-count")
        return dto.count
    }

    func notifications(page: Int = 1) async throws -> [NotificationDTO] {
        let pageData: NotificationsPage = try await client.get(
            "/messages/notifications",
            query: [URLQueryItem(name: "page", value: String(page))]
        )
        return pageData.rows
    }

    func sendCardAttachment(toUserId: String, cardType: String, cardId: String, content: String? = nil) async throws {
        struct Body: Encodable {
            let toUserId: String
            let cardType: String
            let cardId: String
            let content: String?
        }
        struct OK: Decodable {}
        let _: OK = try await client.post(
            "/messages/card-attachment",
            body: Body(toUserId: toUserId, cardType: cardType, cardId: cardId, content: content)
        )
    }

    func merges() async throws -> [MergeChatDTO] {
        try await client.get("/messages/merge")
    }

    func createMerge(title: String, memberIds: [String]) async throws -> MergeChatDTO {
        struct Body: Encodable {
            let title: String
            let memberIds: [String]
        }
        return try await client.post("/messages/merge", body: Body(title: title, memberIds: memberIds))
    }

    func mergeMessages(mergeId: String, page: Int = 1) async throws -> [MessageDTO] {
        try await client.get(
            "/messages/merge/\(mergeId)",
            query: [URLQueryItem(name: "page", value: String(page))]
        )
    }

    func sendMergeMessage(mergeId: String, content: String) async throws {
        struct Body: Encodable { let content: String }
        struct OK: Decodable {}
        let _: OK = try await client.post("/messages/merge/\(mergeId)/send", body: Body(content: content))
    }
}

enum MessageMapper {
    static func mapThread(_ dto: ConversationDTO) -> ChatThread {
        let preview = dto.lastMessage?.content ?? ""
        return ChatThread(
            id: dto.user.id,
            peer: AppUser.from(dto.user),
            preview: preview,
            timeText: APIDate.relativeOrTime(dto.lastMessage?.createdAt),
            unreadCount: dto.unreadCount ?? 0,
            relatedDemandTitle: nil,
            isCommunicating: false,
            isSystem: false,
            remainingCommText: nil
        )
    }

    static func mapBubble(_ dto: MessageDTO, myUserId: String?) -> ChatBubbleKind {
        if dto.type == "SYSTEM" {
            return .system(dto.content)
        }
        let isMine: Bool
        if let myUserId {
            isMine = dto.fromUserId == myUserId
        } else {
            isMine = false
        }
        return .text(dto.content, isMine: isMine)
    }
}
