import SwiftUI

struct AgentChatView: View {
    @Environment(AppSession.self) private var session
    var initialPrompt: String? = nil

    @State private var conversations: [AgentConversationDTO] = []
    @State private var selected: AgentConversationDTO?
    @State private var isLoadingList = false
    @State private var listError: String?
    @State private var didBootstrapPrompt = false
    @State private var pendingDraft: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                NWPaneCaption(text: "智能对话 · 需审批模式")

                HStack(spacing: 8) {
                    Button {
                        Task { await createConversation() }
                    } label: {
                        Label("新对话", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Spacer()

                    Button("刷新") {
                        Task { await loadConversations() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                if let listError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(listError).foregroundStyle(.secondary)
                        Button("重新加载") { Task { await loadConversations() } }
                    }
                    .padding(16)
                    Spacer(minLength: 0)
                } else if isLoadingList && conversations.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                    Spacer(minLength: 0)
                } else if conversations.isEmpty {
                    NWEmptyState(
                        title: "暂无对话",
                        systemImage: "sparkles",
                        message: "点击「新对话」开始与九木助手交流"
                    )
                    Spacer(minLength: 0)
                } else {
                    List(conversations, selection: $selected) { conversation in
                        AgentConversationRow(conversation: conversation)
                            .tag(conversation)
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                            .contextMenu {
                                Button("删除", role: .destructive) {
                                    Task { await deleteConversation(conversation) }
                                }
                            }
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                }
            }
            .paneColumn(minWidth: 280, idealWidth: 300)

            Divider()

            Group {
                if let selected {
                    AgentConversationDetailView(
                        conversation: selected,
                        initialDraft: pendingDraft,
                        onDeleted: {
                            conversations.removeAll { $0.id == selected.id }
                            self.selected = conversations.first
                            pendingDraft = nil
                        },
                        onConversationUpdated: { updated in
                            if let index = conversations.firstIndex(where: { $0.id == updated.id }) {
                                conversations[index] = updated
                            }
                        }
                    )
                } else {
                    NWDetailPlaceholder(
                        title: "选择对话",
                        systemImage: "sparkles",
                        message: "从左侧选择或新建一个对话"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("九木助手")
        .task { await bootstrap() }
    }

    private func bootstrap() async {
        await loadConversations()
        guard !didBootstrapPrompt,
              let prompt = initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
              !prompt.isEmpty
        else { return }
        didBootstrapPrompt = true
        await createConversation(prefill: prompt)
    }

    private func loadConversations() async {
        isLoadingList = true
        listError = nil
        defer { isLoadingList = false }
        do {
            conversations = try await session.agentService.listConversations()
            if selected == nil { selected = conversations.first }
            else if let current = selected,
                    !conversations.contains(where: { $0.id == current.id }) {
                selected = conversations.first
            }
        } catch {
            listError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func createConversation(prefill: String? = nil) async {
        do {
            let created = try await session.agentService.createConversation(title: nil, thinkMode: nil)
            conversations.insert(created, at: 0)
            selected = created
            pendingDraft = prefill
        } catch {
            listError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func deleteConversation(_ conversation: AgentConversationDTO) async {
        do {
            try await session.agentService.deleteConversation(id: conversation.id)
            conversations.removeAll { $0.id == conversation.id }
            if selected?.id == conversation.id {
                selected = conversations.first
            }
        } catch {
            listError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct AgentConversationRow: View {
    let conversation: AgentConversationDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(conversation.title?.isEmpty == false ? conversation.title! : "新对话")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(APIDate.relativeOrTime(conversation.updatedAt ?? conversation.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let preview = conversation.lastMessagePreview, !preview.isEmpty {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AgentConversationDetailView: View {
    let conversation: AgentConversationDTO
    var initialDraft: String? = nil
    var onDeleted: () -> Void
    var onConversationUpdated: (AgentConversationDTO) -> Void

    @Environment(AppSession.self) private var session
    @State private var detail: AgentConversationDetailDTO?
    @State private var draft = ""
    @State private var isLoading = false
    @State private var isSending = false
    @State private var isStreaming = false
    @State private var streamingText = ""
    @State private var streamingThink = ""
    @State private var thinkFinished = false
    @State private var errorMessage: String?
    @State private var streamTask: Task<Void, Never>?
    @State private var streamReceivedChunks = false
    @State private var didApplyInitialDraft = false

    private var displayMessages: [AgentMessageDTO] {
        detail?.messages ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(conversation.title?.isEmpty == false ? conversation.title! : "九木助手")
                    .font(.headline)
                Spacer()
                if isStreaming {
                    NWStatusChip(
                        text: streamingThink.isEmpty || thinkFinished ? "回复中" : "思考中",
                        tint: AppTheme.secondary
                    )
                }
                Button(role: .destructive) {
                    Task { await deleteCurrent() }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除对话")
            }
            .padding(12)
            .background(AppTheme.surface)
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if isLoading && displayMessages.isEmpty && streamingText.isEmpty && streamingThink.isEmpty {
                            ProgressView().padding(.top, 40)
                        }
                        ForEach(displayMessages) { message in
                            agentBubble(message).id(message.id)
                        }
                        if isStreaming, !streamingThink.isEmpty || !streamingText.isEmpty {
                            streamingBubble
                                .id("__streaming__")
                        }
                    }
                    .padding(16)
                }
                .onChange(of: displayMessages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: streamingText) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: streamingThink) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }

            Divider()
            HStack(spacing: 12) {
                TextField("向九木助手提问…", text: $draft, axis: .vertical)
                    .lineLimit(1 ... 4)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await send() } }
                Button {
                    Task { await send() }
                } label: {
                    if isSending || isStreaming {
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
        .task(id: conversation.id) {
            streamTask?.cancel()
            streamTask = nil
            streamingText = ""
            streamingThink = ""
            thinkFinished = false
            didApplyInitialDraft = false
            await loadDetail()
        }
        .onChange(of: initialDraft) { _, _ in
            applyInitialDraftIfNeeded()
        }
        .onDisappear {
            streamTask?.cancel()
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var streamingBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                if !streamingThink.isEmpty {
                    AgentThinkingBlock(
                        text: streamingThink,
                        isLive: !thinkFinished,
                        initiallyExpanded: true
                    )
                }
                if !streamingText.isEmpty {
                    Text(streamingText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(.primary)
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .textSelection(.enabled)
                } else if thinkFinished {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.vertical, 4)
                }
            }
            Spacer(minLength: 80)
        }
    }

    @ViewBuilder
    private func agentBubble(_ message: AgentMessageDTO) -> some View {
        let isUser = message.role.lowercased() == "user"
        HStack {
            if isUser { Spacer(minLength: 80) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                if !isUser, let thinking = message.thinking, !thinking.isEmpty {
                    AgentThinkingBlock(
                        text: thinking,
                        isLive: false,
                        initiallyExpanded: false
                    )
                }
                if !message.content.isEmpty {
                    Text(message.content)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(isUser ? .white : .primary)
                        .background(isUser ? AppTheme.primary : AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .textSelection(.enabled)
                }
            }
            if !isUser { Spacer(minLength: 80) }
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && !isStreaming
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        let anchorId = isStreaming ? "__streaming__" : displayMessages.last?.id
        guard let anchorId else { return }
        withAnimation { proxy.scrollTo(anchorId, anchor: .bottom) }
    }

    private func loadDetail() async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await session.agentService.getConversation(id: conversation.id)
            applyInitialDraftIfNeeded()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func applyInitialDraftIfNeeded() {
        guard !didApplyInitialDraft,
              let initialDraft,
              !initialDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              displayMessages.isEmpty
        else { return }
        draft = initialDraft
        didApplyInitialDraft = true
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isSending = true
        draft = ""
        defer { isSending = false }

        appendLocalUserMessage(text)
        await streamOrFallback(text: text)
    }

    private func appendLocalUserMessage(_ text: String) {
        let userMessage = AgentMessageDTO(
            id: UUID().uuidString,
            role: "user",
            content: text
        )
        if detail != nil {
            detail = AgentConversationDetailDTO(
                id: detail!.id,
                title: detail!.title,
                thinkMode: detail!.thinkMode,
                createdAt: detail!.createdAt,
                updatedAt: detail!.updatedAt,
                messages: detail!.messages + [userMessage]
            )
        } else {
            detail = AgentConversationDetailDTO(
                id: conversation.id,
                title: conversation.title,
                thinkMode: conversation.thinkMode,
                createdAt: conversation.createdAt,
                updatedAt: conversation.updatedAt,
                messages: [userMessage]
            )
        }
    }

    private func streamOrFallback(text: String) async {
        isStreaming = true
        streamingText = ""
        streamingThink = ""
        thinkFinished = false
        streamReceivedChunks = false

        let failed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            var resumed = false
            func finish(failed: Bool) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: failed)
            }

            streamTask?.cancel()
            streamTask = session.agentService.streamReply(
                conversationId: conversation.id,
                message: text,
                thinkMode: true,
                onEvent: { event, data in
                    Task { @MainActor in
                        streamReceivedChunks = true
                        handleStreamEvent(event: event, data: data)
                    }
                },
                onDone: {
                    Task { @MainActor in
                        isStreaming = false
                        streamingText = ""
                        streamingThink = ""
                        thinkFinished = false
                        finish(failed: false)
                    }
                },
                onError: { error in
                    Task { @MainActor in
                        isStreaming = false
                        streamingText = ""
                        streamingThink = ""
                        thinkFinished = false
                        errorMessage = (error as? LocalizedError)?.errorDescription
                            ?? error.localizedDescription
                        finish(failed: true)
                    }
                }
            )
        }

        if failed {
            if streamReceivedChunks {
                await loadDetail()
                await refreshListItem()
            } else {
                await sendNonStreamFallback(text: text)
            }
        } else {
            await loadDetail()
            await refreshListItem()
        }
    }

    private func handleStreamEvent(event: String, data: String) {
        let lowered = event.lowercased()
        if lowered == "done" || lowered == "end" || lowered == "complete" {
            return
        }
        if lowered == "think-end" {
            thinkFinished = true
            return
        }
        if lowered == "error" {
            streamTask?.cancel()
            return
        }

        guard let jsonData = data.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else {
            if !data.isEmpty, lowered.contains("delta") || lowered.contains("text") || lowered.contains("message") {
                streamingText += data
            }
            return
        }

        if lowered == "think" {
            let chunk = obj["line"] as? String ?? obj["delta"] as? String ?? obj["content"] as? String ?? ""
            if !chunk.isEmpty {
                streamingThink += chunk
            }
            return
        }

        if let chunk = obj["delta"] as? String ?? obj["content"] as? String ?? obj["text"] as? String,
           !chunk.isEmpty {
            if !streamingThink.isEmpty {
                thinkFinished = true
            }
            streamingText += chunk
        }
    }

    private func sendNonStreamFallback(text: String) async {
        do {
            _ = try await session.agentService.sendMessageNonStream(id: conversation.id, message: text)
            await loadDetail()
            await refreshListItem()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func refreshListItem() async {
        do {
            let list = try await session.agentService.listConversations()
            if let updated = list.first(where: { $0.id == conversation.id }) {
                onConversationUpdated(updated)
            }
        } catch {
            // Non-critical; list refresh can wait for manual reload.
        }
    }

    private func deleteCurrent() async {
        do {
            streamTask?.cancel()
            try await session.agentService.deleteConversation(id: conversation.id)
            onDeleted()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Cursor 风格：可折叠思考过程
private struct AgentThinkingBlock: View {
    let text: String
    var isLive: Bool = false
    var initiallyExpanded: Bool = false

    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.caption)
                    Text(isLive ? "Thinking…" : "Thought")
                        .font(.caption.weight(.medium))
                    if isLive {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(AppTheme.fill.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .textSelection(.enabled)
            }
        }
        .onAppear {
            expanded = initiallyExpanded || isLive
        }
        .onChange(of: isLive) { _, live in
            if live { expanded = true }
        }
    }
}
