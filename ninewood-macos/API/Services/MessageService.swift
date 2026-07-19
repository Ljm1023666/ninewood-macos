import Foundation

@MainActor
final class MessageService: MessageUnreadCounting {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func conversations() async throws -> [ChatThread] {
        let list: [ConversationDTO] = try await client.get("/messages/conversations")
        return list.map(MessageMapperSupport.mapThread)
    }

    func messages(with userId: String, myUserId: String, page: Int = 1) async throws -> [ChatBubbleKind] {
        let list: [MessageDTO] = try await client.get(
            "/messages/\(userId)",
            query: [URLQueryItem(name: "page", value: String(page))]
        )
        return list.map { MessageMapperSupport.mapBubble($0, myUserId: myUserId) }
    }

    func send(toUserId: String, content: String, file: MultipartFile? = nil) async throws -> MessageDTO {
        if let file {
            return try await client.postMultipart(
                "/messages/send",
                fields: [
                    "toUserId": toUserId,
                    "content": content
                ],
                files: [file]
            )
        }
        return try await client.post(
            "/messages/send",
            body: SendMessageBody(toUserId: toUserId, content: content)
        )
    }

    func unreadCount() async throws -> Int {
        let dto: UnreadCountDTO = try await client.get("/messages/unread-count")
        return dto.count
    }

    func notifications(page: Int = 1) async throws -> NotificationsPage {
        try await client.get(
            "/messages/notifications",
            query: [URLQueryItem(name: "page", value: String(page))]
        )
    }

    func markNotificationRead(id: String) async throws {
        struct OK: Decodable {}
        let _: OK = try await client.post("/messages/notifications/\(id)/read")
    }

    func markAllNotificationsRead() async throws {
        struct OK: Decodable {}
        let _: OK = try await client.post("/messages/notifications/read-all")
    }

    func sendCardAttachment(
        toUserId: String,
        cardType: String,
        cardId: String,
        content: String? = nil
    ) async throws -> MessageDTO {
        struct Body: Encodable {
            let toUserId: String
            let cardType: String
            let cardId: String
            let content: String?
        }
        return try await client.post(
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

    func sendMergeMessage(mergeId: String, content: String, file: MultipartFile? = nil) async throws {
        struct OK: Decodable {}
        if let file {
            let _: OK = try await client.postMultipart(
                "/messages/merge/\(mergeId)/send",
                fields: ["content": content],
                files: [file]
            )
        } else {
            struct Body: Encodable { let content: String }
            let _: OK = try await client.post(
                "/messages/merge/\(mergeId)/send",
                body: Body(content: content)
            )
        }
    }

    func addMergeMembers(id: String, userIds: [String]) async throws -> MergeChatDTO {
        struct Body: Encodable { let userIds: [String] }
        return try await client.post(
            "/messages/merge/\(id)/members",
            body: Body(userIds: userIds)
        )
    }

    func leaveMerge(id: String) async throws {
        struct OK: Decodable {}
        let _: OK = try await client.delete("/messages/merge/\(id)/members/me")
    }

    func muteMerge(id: String, muted: Bool) async throws {
        struct Body: Encodable { let muted: Bool }
        struct OK: Decodable {}
        let _: OK = try await client.put(
            "/messages/merge/\(id)/mute",
            body: Body(muted: muted)
        )
    }

    func mergeFiles(id: String, page: Int = 1) async throws -> [MessageDTO] {
        struct Page: Decodable {
            let items: [MessageDTO]?
            let messages: [MessageDTO]?
            let files: [MessageDTO]?
        }
        if let rows: [MessageDTO] = try? await client.get(
            "/messages/merge/\(id)/files",
            query: [URLQueryItem(name: "page", value: String(page))]
        ) {
            return rows
        }
        let pageData: Page = try await client.get(
            "/messages/merge/\(id)/files",
            query: [URLQueryItem(name: "page", value: String(page))]
        )
        return pageData.items ?? pageData.messages ?? pageData.files ?? []
    }
}
