import SwiftUI

struct MessagesView: View {
    @Environment(AppSession.self) private var session
    @State private var searchText = ""
    @State private var threads: [ChatThread] = []
    @State private var selected: ChatThread?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showNotifications = false

    private var filtered: [ChatThread] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return threads }
        return threads.filter {
            $0.peer.name.localizedCaseInsensitiveContains(q)
                || $0.preview.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                NWPaneCaption(text: session.chatRealtime.isConnected ? "实时已连接" : "可手动刷新")

                HStack(spacing: AppTheme.space8) {
                    NWSearchBar(text: $searchText, placeholder: "搜索联系人或内容")
                    if session.chatRealtime.isConnected {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(AppTheme.openStatus)
                            .help("实时已连接")
                    }
                }
                .padding(.horizontal, AppTheme.space16)
                .padding(.bottom, AppTheme.space12)

                if let loadError {
                    VStack(alignment: .leading, spacing: AppTheme.space8) {
                        Text(loadError).foregroundStyle(.secondary)
                        Button("重新加载") { Task { await loadThreads() } }
                    }
                    .padding(AppTheme.space16)
                    Spacer(minLength: 0)
                } else if isLoading && threads.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                    Spacer(minLength: 0)
                } else if filtered.isEmpty {
                    NWEmptyState(
                        title: "暂无消息",
                        systemImage: "bubble.left.and.bubble.right",
                        message: "请求接单并沟通后会出现会话"
                    )
                    Spacer(minLength: 0)
                } else {
                    List(filtered, selection: $selected) { thread in
                        MessageRowView(thread: thread)
                            .tag(thread)
                            .listRowInsets(EdgeInsets(
                                top: AppTheme.space8,
                                leading: AppTheme.space12,
                                bottom: AppTheme.space8,
                                trailing: AppTheme.space12
                            ))
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                }
            }
            .paneColumn(minWidth: 300, idealWidth: 340)

            Divider()

            Group {
                if let selected {
                    ChatDetailView(thread: selected) {
                        clearUnread(for: selected.id)
                    }
                } else {
                    NWDetailPlaceholder(
                        title: "选择会话",
                        systemImage: "bubble.left",
                        message: "从左侧选择一位联系人开始聊天"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("消息")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("通知") { showNotifications = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("刷新") {
                    Task {
                        await loadThreads()
                        await session.refreshUnread()
                    }
                }
            }
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsView()
                .environment(session)
                .frame(minWidth: 480, minHeight: 520)
        }
        .task {
            await loadThreads()
            await session.refreshUnread()
        }
        .onChange(of: session.chatRealtime.inboxEpoch) { _, _ in
            Task {
                await loadThreads()
                await session.refreshUnread()
            }
        }
        .onChange(of: selected?.id) { _, newId in
            if let newId { clearUnread(for: newId) }
        }
    }

    private func clearUnread(for threadId: String) {
        guard let idx = threads.firstIndex(where: { $0.id == threadId }) else { return }
        let unread = threads[idx].unreadCount
        guard unread > 0 else { return }
        threads[idx].unreadCount = 0
        session.applyLocalRead(count: unread)
    }

    private func loadThreads() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            threads = try await session.messageService.conversations()
            if selected == nil { selected = threads.first }
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct MessageRowView: View {
    let thread: ChatThread

    var body: some View {
        HStack(spacing: 12) {
            NWAvatarView(
                url: thread.peer.avatarMediaURL,
                name: thread.peer.name,
                size: 40
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(thread.peer.name).font(.body.weight(.semibold))
                    Spacer()
                    Text(thread.timeText).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text(thread.preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if thread.unreadCount > 0 {
                        Text("\(thread.unreadCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.error)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ChatDetailView: View {
    let thread: ChatThread
    var onOpened: (() -> Void)? = nil
    @Environment(AppSession.self) private var session
    @State private var draft = ""
    @State private var bubbles: [ChatBubbleKind] = []
    @State private var isLoading = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var seenRealtimeIds: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                NWAvatarView(
                    url: thread.peer.avatarMediaURL,
                    name: thread.peer.name,
                    size: 34
                )
                Text(thread.peer.name).font(.headline)
                Spacer()
                if let title = thread.relatedDemandTitle {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .background(AppTheme.surface)
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if isLoading && bubbles.isEmpty {
                            ProgressView().padding(.top, 40)
                        }
                        ForEach(Array(bubbles.enumerated()), id: \.offset) { index, bubble in
                            bubbleView(bubble).id(index)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: bubbles.count) { _, _ in
                    if let last = bubbles.indices.last {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }

            Divider()
            HStack(spacing: 12) {
                TextField("发送消息…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await send() } }
                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSend)
            }
            .padding(12)
        }
        .background(AppTheme.workspaceBackground)
        .task { await loadMessages() }
        .onChange(of: session.chatRealtime.lastIncoming) { _, incoming in
            guard let incoming else { return }
            appendRealtimeIfNeeded(incoming)
        }
        .alert("发送失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func bubbleView(_ bubble: ChatBubbleKind) -> some View {
        switch bubble {
        case .system(let text):
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        case .time(let text):
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        case .text(let text, let isMine):
            HStack {
                if isMine { Spacer(minLength: 80) }
                Text(text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(isMine ? .white : .primary)
                    .background(isMine ? AppTheme.primary : AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                if !isMine { Spacer(minLength: 80) }
            }
        case .demandCard:
            EmptyView()
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private func loadMessages() async {
        isLoading = true
        defer { isLoading = false }
        onOpened?()
        do {
            let myId = session.currentUserId ?? ""
            bubbles = try await session.messageService.messages(with: thread.peer.id, myUserId: myId)
            await session.refreshUnread()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            _ = try await session.messageService.send(toUserId: thread.peer.id, content: text)
            draft = ""
            bubbles.append(.text(text, isMine: true))
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func appendRealtimeIfNeeded(_ incoming: RealtimeIncomingMessage) {
        guard !seenRealtimeIds.contains(incoming.id) else { return }
        let myId = session.currentUserId ?? ""
        let involvesPeer =
            (incoming.fromUserId == thread.peer.id && incoming.toUserId == myId)
            || (incoming.fromUserId == myId && incoming.toUserId == thread.peer.id)
        guard involvesPeer else { return }
        seenRealtimeIds.insert(incoming.id)
        // 自己发的 REST 已本地追加；实时回显跳过
        if incoming.fromUserId == myId { return }
        bubbles.append(.text(incoming.content, isMine: false))
    }
}
