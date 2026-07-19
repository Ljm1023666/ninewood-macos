import Foundation

/// 消息 DTO → 领域模型映射（与 UI 解耦，供 Service / Repository 共用）。
enum MessageMapperSupport {
    static func mapThread(_ dto: ConversationDTO) -> ChatThread {
        let preview = previewText(for: dto.lastMessage)
        let communication = dto.communication.map {
            CommunicationContext(
                applicantID: $0.applicantId,
                demandID: $0.demandId,
                demandTitle: $0.demandTitle,
                deadline: APIDate.parse($0.commDeadline),
                canExtend: $0.canExtend ?? false,
                extensionMinutes: $0.extensionMinutes ?? 0
            )
        }
        let lastType = dto.lastMessage?.type?.uppercased()
        let isSystem = lastType == "SYSTEM" || dto.user.id == "system"

        return ChatThread(
            id: dto.user.id,
            peer: AppUser.from(dto.user),
            preview: preview,
            timeText: APIDate.relativeOrTime(dto.lastMessage?.createdAt),
            unreadCount: dto.unreadCount ?? 0,
            relatedDemandTitle: communication?.demandTitle,
            isCommunicating: communication != nil,
            isSystem: isSystem,
            remainingCommText: communication?.remainingText(),
            communication: communication
        )
    }

    static func mapBubble(_ dto: MessageDTO, myUserId: String?) -> ChatBubbleKind {
        let type = dto.type?.uppercased()
        if type == "SYSTEM" {
            return .system(dto.content)
        }

        let isMine: Bool
        if let myUserId {
            isMine = dto.fromUserId == myUserId
        } else {
            isMine = false
        }
        let sender = sender(from: dto)

        if let attachment = dto.cardAttachment {
            return .card(mapCardAttachment(attachment, fallbackContent: dto.content, isMine: isMine), sender: sender)
        }

        switch type {
        case "IMAGE":
            let label = dto.content.hasPrefix("/") || dto.content.hasPrefix("http")
                ? dto.content
                : "[图片]"
            return .text(label, isMine: isMine, sender: sender)
        case "VIDEO":
            return .text(dto.content.isEmpty ? "[视频]" : dto.content, isMine: isMine, sender: sender)
        case "VOICE":
            return .text("[语音]", isMine: isMine, sender: sender)
        default:
            return .text(dto.content, isMine: isMine, sender: sender)
        }
    }

    private static func sender(from dto: MessageDTO) -> ChatBubbleSender {
        let nickname = dto.fromUser?.nickname?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String
        if let nickname, !nickname.isEmpty {
            name = nickname
        } else {
            let id = dto.fromUserId
            name = id.count <= 8 ? id : String(id.prefix(8))
        }
        return ChatBubbleSender(
            userId: dto.fromUserId,
            name: name,
            avatarURL: dto.fromUser?.avatarMediaURL
        )
    }

    static func previewText(for message: MessageDTO?) -> String {
        guard let message else { return "" }
        if message.cardAttachment != nil {
            let kind = message.cardAttachment?.cardType.uppercased()
            return kind == "SERVICE_CARD" ? "[服务卡]" : "[需求卡]"
        }
        switch message.type?.uppercased() {
        case "SYSTEM":
            return message.content
        case "IMAGE":
            return "[图片]"
        case "VIDEO":
            return "[视频]"
        case "VOICE":
            return "[语音]"
        default:
            return message.content
        }
    }

    private static func mapCardAttachment(
        _ attachment: CardAttachmentDTO,
        fallbackContent: String,
        isMine: Bool
    ) -> ChatCardAttachment {
        let snapshot = attachment.snapshot
        let kind = ChatCardAttachment.Kind(rawValue: attachment.cardType) ?? .unknown
        return ChatCardAttachment(
            id: attachment.id,
            kind: kind,
            cardID: attachment.demandId
                ?? attachment.serviceCardId
                ?? snapshot?.cardId,
            title: snapshot?.title
                ?? (kind == .demand ? "需求卡" : "服务卡"),
            summary: snapshot?.summary ?? snapshot?.description ?? fallbackContent,
            price: snapshot?.minPrice?.value ?? snapshot?.priceMin?.value,
            status: snapshot?.status,
            coverImage: snapshot?.coverImage ?? snapshot?.coverUrl,
            isMine: isMine
        )
    }
}
