import Foundation
import Observation

@Observable
@MainActor
final class ChatDetailFeatureModel {
    private(set) var thread: ChatThread
    var draft = ""
    private(set) var bubbles: [ChatBubbleKind] = []
    private(set) var isLoading = false
    private(set) var isSending = false
    var errorMessage: String?

    private let repository: MessageRepository
    private let currentUserID: String
    private let isPreview: Bool
    private var seenRealtimeIDs: Set<String> = []

    init(
        thread: ChatThread,
        currentUserID: String,
        repository: MessageRepository,
        previewBubbles: [ChatBubbleKind]? = nil
    ) {
        self.thread = thread
        self.currentUserID = currentUserID
        self.repository = repository
        self.isPreview = previewBubbles != nil
        self.bubbles = previewBubbles ?? []
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    func load() async {
        guard !isPreview else { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            bubbles = try await repository.messages(
                peerID: thread.peer.id,
                currentUserID: currentUserID
            )
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// 列表刷新后只更新元数据，不拆掉气泡缓存。
    func applyThreadMetadata(_ thread: ChatThread) {
        guard thread.peer.id == self.thread.peer.id else { return }
        self.thread = thread
    }

    func send() async {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }

        do {
            try await repository.send(peerID: thread.peer.id, content: content)
            draft = ""
            bubbles.append(.text(content, isMine: true, sender: nil))
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func sendCard(
        type: ChatCardAttachment.Kind,
        cardID: String,
        content: String? = nil
    ) async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            let bubble = try await repository.sendCard(
                peerID: thread.peer.id,
                type: type,
                cardID: cardID,
                content: content
            )
            bubbles.append(bubble)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func updateCommunication(deadline: Date?, addedMinutes: Int) {
        guard let current = thread.communication else { return }
        let updated = CommunicationContext(
            applicantID: current.applicantID,
            demandID: current.demandID,
            demandTitle: current.demandTitle,
            deadline: deadline ?? current.deadline?.addingTimeInterval(Double(addedMinutes * 60)),
            canExtend: current.canExtend,
            extensionMinutes: current.extensionMinutes + addedMinutes
        )
        thread.communication = updated
        thread.remainingCommText = updated.remainingText()
    }

    func appendRealtime(_ incoming: RealtimeIncomingMessage) {
        guard !seenRealtimeIDs.contains(incoming.id) else { return }
        let involvesPeer =
            (incoming.fromUserId == thread.peer.id && (incoming.toUserId.isEmpty || incoming.toUserId == currentUserID))
            || (incoming.fromUserId == currentUserID && (incoming.toUserId.isEmpty || incoming.toUserId == thread.peer.id))
        guard involvesPeer else { return }
        guard incoming.mergeId == nil else { return }

        seenRealtimeIDs.insert(incoming.id)
        // REST 发送成功时已本地追加；跳过自己的 Socket 回显。
        guard incoming.fromUserId != currentUserID else { return }
        bubbles.append(.text(incoming.content, isMine: false, sender: nil))
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
