import Foundation

/// 消息领域的数据入口；实时事件仍由 ChatRealtime 提供，历史记录以 API 为准。
@MainActor
final class MessageRepository {
    private let service: MessageService

    init(service: MessageService) {
        self.service = service
    }

    func conversations() async throws -> [ChatThread] {
        try await service.conversations()
    }

    func messages(peerID: String, currentUserID: String, page: Int = 1) async throws -> [ChatBubbleKind] {
        try await service.messages(with: peerID, myUserId: currentUserID, page: page)
    }

    func send(peerID: String, content: String) async throws {
        _ = try await service.send(toUserId: peerID, content: content)
    }

    func unreadCount() async throws -> Int {
        try await service.unreadCount()
    }

    func notifications(page: Int = 1) async throws -> NotificationsPage {
        try await service.notifications(page: page)
    }

    func markNotificationRead(id: String) async throws {
        try await service.markNotificationRead(id: id)
    }

    func markAllNotificationsRead() async throws {
        try await service.markAllNotificationsRead()
    }

    func sendCard(
        peerID: String,
        type: ChatCardAttachment.Kind,
        cardID: String,
        content: String? = nil
    ) async throws -> ChatBubbleKind {
        let dto = try await service.sendCardAttachment(
            toUserId: peerID,
            cardType: type.rawValue,
            cardId: cardID,
            content: content
        )
        return MessageMapperSupport.mapBubble(dto, myUserId: dto.fromUserId)
    }

    func merges() async throws -> [MergeChatDTO] {
        try await service.merges()
    }

    func createMerge(title: String, memberIds: [String]) async throws -> MergeChatDTO {
        try await service.createMerge(title: title, memberIds: memberIds)
    }

    func mergeMessages(mergeID: String, currentUserID: String, page: Int = 1) async throws -> [ChatBubbleKind] {
        let list = try await service.mergeMessages(mergeId: mergeID, page: page)
        let timeline = MessageMergeDeduper.timeline(list, viewerID: currentUserID)
        return timeline.map { MessageMapperSupport.mapBubble($0, myUserId: currentUserID) }
    }

    func sendMergeMessage(mergeID: String, content: String, file: MultipartFile? = nil) async throws {
        try await service.sendMergeMessage(mergeId: mergeID, content: content, file: file)
    }
}
