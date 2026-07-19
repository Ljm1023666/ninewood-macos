import Foundation
import Observation

@MainActor
protocol ConversationListing {
    func conversations() async throws -> [ChatThread]
}

@Observable
@MainActor
final class MessagesFeatureModel {
    var searchText = ""
    private(set) var threads: [ChatThread] = []
    /// 选中态以 peer/thread ID 为准，避免 `load()` 用过期快照冲掉点击。
    private(set) var selectedID: String?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// 找人/关注「发消息」等入口：后续 `load()` 不得冲掉该聚焦。
    private(set) var stickyFocusPeerID: String?

    /// 已打开过的会话：全量刷新后仍清零未读，避免徽章弹回。
    private var openedPeerIDs: Set<String> = []
    private var loadGeneration = 0

    private let repository: (any ConversationListing)?
    private let isPreview: Bool

    init(repository: any ConversationListing) {
        self.repository = repository
        self.isPreview = false
    }

    init(previewThreads: [ChatThread]) {
        self.repository = nil
        self.isPreview = true
        self.threads = previewThreads
        self.selectedID = previewThreads.first?.id
    }

    init(repository: any ConversationListing, previewThreads: [ChatThread]?) {
        self.repository = repository
        self.isPreview = previewThreads != nil
        self.threads = previewThreads ?? []
        self.selectedID = previewThreads?.first?.id
    }

    var selected: ChatThread? {
        get {
            guard let selectedID else { return nil }
            return threads.first(where: { $0.id == selectedID })
        }
        set {
            selectedID = newValue?.id
            guard let newValue,
                  let index = threads.firstIndex(where: { $0.id == newValue.id }) else { return }
            threads[index] = newValue
        }
    }

    var filteredThreads: [ChatThread] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return threads }
        return threads.filter {
            $0.peer.name.localizedCaseInsensitiveContains(query)
                || $0.preview.localizedCaseInsensitiveContains(query)
        }
    }

    func clearStickyFocus() {
        stickyFocusPeerID = nil
    }

    /// 在 `load()` 之前标记目标私聊，避免并发刷新冲掉选中态。
    func beginFocus(peerID: String) {
        stickyFocusPeerID = peerID
        selectedID = peerID
    }

    func load() async {
        guard !isPreview else { return }
        guard let repository else { return }
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        defer {
            if generation == loadGeneration {
                isLoading = false
            }
        }

        do {
            let rows = try await repository.conversations()
            guard generation == loadGeneration else { return }

            var merged = rows
            // 保留合成空线程（尚无历史）
            if let sticky = stickyFocusPeerID,
               !merged.contains(where: { $0.peer.id == sticky }),
               let synthetic = threads.first(where: { $0.peer.id == sticky }) {
                merged.insert(synthetic, at: 0)
            }

            // 已打开会话：服务端未读尚未清零时保持本地清零
            for index in merged.indices {
                if openedPeerIDs.contains(merged[index].id) {
                    merged[index].unreadCount = 0
                }
            }

            threads = merged

            let prefer = stickyFocusPeerID ?? selectedID
            if let prefer, merged.contains(where: { $0.id == prefer || $0.peer.id == prefer }) {
                selectedID = prefer
            } else if selectedID == nil {
                // 仅首次无选中时自动选第一条；已有选中但列表暂无该项时保持 ID，勿跳到 first
                selectedID = merged.first?.id
            }
            // selectedID 指向的会话暂时不在列表：保留 ID，等 sticky/focus 或下次刷新
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Socket 到达时只改一条预览，避免全量 `conversations()`。
    func applyIncomingPreview(_ incoming: RealtimeIncomingMessage, currentUserID: String) {
        guard incoming.mergeId == nil else { return }
        let peerID: String = {
            if incoming.fromUserId == currentUserID { return incoming.toUserId }
            return incoming.fromUserId
        }()
        guard !peerID.isEmpty else { return }

        let preview = incoming.content.isEmpty
            ? (incoming.hasCardAttachment ? "[卡片]" : "新消息")
            : incoming.content
        let timeText = Self.shortTime(incoming.createdAt)
        let isOpen = selectedID == peerID || openedPeerIDs.contains(peerID)

        if let index = threads.firstIndex(where: { $0.peer.id == peerID }) {
            threads[index].preview = preview
            threads[index].timeText = timeText
            if !isOpen, incoming.fromUserId != currentUserID {
                threads[index].unreadCount += 1
            } else {
                threads[index].unreadCount = 0
            }
            let updated = threads.remove(at: index)
            threads.insert(updated, at: 0)
        } else if incoming.fromUserId != currentUserID {
            // 新会话：轻量占位，完整资料留给下一次手动/防抖刷新
            let thread = ChatThread(
                id: peerID,
                peer: AppUser(
                    id: peerID,
                    name: "用户",
                    avatarUrl: nil,
                    coverUrl: nil,
                    demandCardCoverUrl: nil,
                    creditScore: 60,
                    completedOrders: 0,
                    goodRate: 0
                ),
                preview: preview,
                timeText: timeText,
                unreadCount: isOpen ? 0 : 1,
                relatedDemandTitle: nil,
                isCommunicating: false,
                isSystem: false,
                remainingCommText: nil
            )
            threads.insert(thread, at: 0)
        }
    }

    @discardableResult
    func clearUnread(threadID: String) -> Int {
        openedPeerIDs.insert(threadID)
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return 0 }
        let count = threads[index].unreadCount
        guard count > 0 else { return 0 }
        threads[index].unreadCount = 0
        return count
    }

    /// 选中与 `peerID` 的私聊；无历史会话时插入空线程并选中。
    func focusPeer(_ peerID: String, fetchUser: () async throws -> SoftUserDTO) async {
        stickyFocusPeerID = peerID
        selectedID = peerID
        openedPeerIDs.insert(peerID)

        if let match = threads.first(where: { $0.peer.id == peerID }) {
            selectedID = match.id
            return
        }
        do {
            let user = try await fetchUser()
            let thread = ChatThread(
                id: user.id,
                peer: AppUser.from(user),
                preview: "开始对话",
                timeText: "现在",
                unreadCount: 0,
                relatedDemandTitle: nil,
                isCommunicating: false,
                isSystem: false,
                remainingCommText: nil
            )
            threads.removeAll { $0.peer.id == peerID }
            threads.insert(thread, at: 0)
            selectedID = thread.id
        } catch {
            let thread = ChatThread(
                id: peerID,
                peer: AppUser(
                    id: peerID,
                    name: "用户",
                    avatarUrl: nil,
                    coverUrl: nil,
                    demandCardCoverUrl: nil,
                    creditScore: 60,
                    completedOrders: 0,
                    goodRate: 0
                ),
                preview: "开始对话",
                timeText: "现在",
                unreadCount: 0,
                relatedDemandTitle: nil,
                isCommunicating: false,
                isSystem: false,
                remainingCommText: nil
            )
            threads.removeAll { $0.peer.id == peerID }
            threads.insert(thread, at: 0)
            selectedID = thread.id
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func selectThread(_ thread: ChatThread) {
        if stickyFocusPeerID != nil, thread.peer.id != stickyFocusPeerID {
            stickyFocusPeerID = nil
        }
        selectedID = thread.id
        openedPeerIDs.insert(thread.id)
    }

    private static func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "M/d"
        }
        return formatter.string(from: date)
    }
}
