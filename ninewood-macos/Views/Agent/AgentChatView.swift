import SwiftUI

struct AgentChatView: View {
    @Environment(AppSession.self) private var session
    var initialPrompt: String? = nil

    @AppStorage("agent.conversationSidebarExpanded") private var isSidebarExpanded = true
    @State private var conversations: [AgentConversationDTO] = []
    @State private var selected: AgentConversationDTO?
    @State private var isLoadingList = false
    @State private var listError: String?
    @State private var didBootstrapPrompt = false
    @State private var pendingDraft: String?
    private let previewDetails: [String: AgentConversationDetailDTO]?

    init(
        initialPrompt: String? = nil,
        previewDetails: [String: AgentConversationDetailDTO]? = nil
    ) {
        self.initialPrompt = initialPrompt
        self.previewDetails = previewDetails
        let rows = previewDetails?.values.map {
            AgentConversationDTO(
                id: $0.id,
                title: $0.title,
                thinkMode: $0.thinkMode,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                lastMessagePreview: $0.messages.last?.content,
                messageCount: $0.messages.count
            )
        }.sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") } ?? []
        _conversations = State(initialValue: rows)
        _selected = State(initialValue: rows.first)
    }

    var body: some View {
        HStack(spacing: 0) {
            NWCollapsibleSidebar(
                isExpanded: isSidebarExpanded,
                expandedWidth: 280,
                collapsedWidth: 52
            ) {
                conversationSidebar
            } collapsed: {
                collapsedConversationRail
            }

            Group {
                if let selected {
                    AgentConversationDetailView(
                        conversation: selected,
                        previewDetail: previewDetails?[selected.id],
                        initialDraft: pendingDraft,
                        isSidebarExpanded: isSidebarExpanded,
                        onToggleSidebar: toggleSidebar,
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
                    .frame(maxWidth: previewDetails != nil ? .infinity : .infinity)
                } else {
                    VStack(spacing: 0) {
                        agentChromeBar(title: "九木助手")
                        Divider()
                        NWDetailPlaceholder(
                            title: "选择对话",
                            systemImage: "sparkles",
                            message: isSidebarExpanded
                                ? "从左侧选择或新建一个对话"
                                : "展开侧栏选择对话，或点击「新对话」"
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("九木助手")
        .task { await bootstrap() }
    }

    private var conversationSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                NWPanelToggleButton(
                    role: .conversations,
                    isExpanded: true,
                    action: toggleSidebar
                )
                Text("对话")
                    .font(.headline)
                Spacer(minLength: 0)
                Button {
                    Task { await createConversation() }
                } label: {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("新对话")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Text("智能对话 · 需审批模式")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            HStack(spacing: 8) {
                Button {
                    Task { await createConversation() }
                } label: {
                    Label("新对话", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    Task { await loadConversations() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("刷新")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            if let listError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(listError).foregroundStyle(.secondary)
                    if let until = session.apiClient.rateLimitedUntil, until > Date() {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let remaining = max(0, Int(ceil(until.timeIntervalSince(context.date))))
                            Text(remaining > 0 ? "写操作冷却剩余 \(remaining) 秒；列表可随时重试" : "冷却已结束，可重新加载")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
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
                        .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
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
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppTheme.workspaceBackground)
    }

    /// 折叠轨只保留「新对话」，展开入口统一放在聊天顶栏，避免双按钮并排。
    private var collapsedConversationRail: some View {
        VStack(spacing: 10) {
            Button {
                Task { await createConversation() }
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("新对话")
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.workspaceBackground)
    }

    private func agentChromeBar(title: String) -> some View {
        HStack(spacing: 10) {
            if !isSidebarExpanded {
                NWPanelToggleButton(
                    role: .conversations,
                    isExpanded: false,
                    action: toggleSidebar
                )
            }
            Text(title).font(.headline)
            Spacer()
        }
        .padding(12)
        .background(AppTheme.surface)
    }

    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSidebarExpanded.toggle()
        }
    }

    private func bootstrap() async {
        if previewDetails != nil { return }
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
            let preferDeep = UserDefaults.standard.object(forKey: AgentReplyMode.defaultsKey) as? Bool ?? true
            let created = try await session.agentService.createConversation(
                title: nil,
                thinkMode: preferDeep
            )
            conversations.insert(created, at: 0)
            selected = created
            pendingDraft = prefill
            if !isSidebarExpanded {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSidebarExpanded = true
                }
            }
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

private enum AgentReplyMode: String, CaseIterable, Identifiable {
    case fast
    case deep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: return "快速"
        case .deep: return "深度思考"
        }
    }

    var thinkMode: Bool { self == .deep }

    static let defaultsKey = "agent.preferDeepThink"

    static func preferred() -> AgentReplyMode {
        let deep = UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
        return deep ? .deep : .fast
    }

    static func from(thinkMode: Bool?) -> AgentReplyMode {
        (thinkMode ?? true) ? .deep : .fast
    }

    func persist() {
        UserDefaults.standard.set(thinkMode, forKey: Self.defaultsKey)
    }
}

private struct AgentConversationDetailView: View {
    let conversation: AgentConversationDTO
    var previewDetail: AgentConversationDetailDTO? = nil
    var initialDraft: String? = nil
    var isSidebarExpanded: Bool = true
    var onToggleSidebar: (() -> Void)? = nil
    var onDeleted: () -> Void
    var onConversationUpdated: (AgentConversationDTO) -> Void

    @Environment(AppSession.self) private var session
    @State private var detail: AgentConversationDetailDTO?
    @State private var draft = ""
    @State private var replyMode: AgentReplyMode = .preferred()
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
    @State private var pendingTool: AgentPendingToolEvent?
    @State private var isResolvingTool = false

    private var displayMessages: [AgentMessageDTO] {
        detail?.messages ?? []
    }

    var body: some View {
        HStack(spacing: 0) {
            chatColumn
            if previewDetail != nil {
                Divider()
                AgentToolResultsRail()
                    .frame(width: 300)
            }
        }
        .background(AppTheme.workspaceBackground)
        .task(id: conversation.id) {
            streamTask?.cancel()
            streamTask = nil
            streamingText = ""
            streamingThink = ""
            thinkFinished = false
            pendingTool = nil
            isResolvingTool = false
            didApplyInitialDraft = false
            replyMode = AgentReplyMode.from(thinkMode: conversation.thinkMode)
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
        .sheet(item: $pendingTool) { tool in
            AgentToolApprovalSheet(
                tool: tool,
                isBusy: isResolvingTool,
                onApprove: { Task { await resolvePendingTool(approved: true) } },
                onReject: { Task { await resolvePendingTool(approved: false) } }
            )
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
                    NWMarkdownChatText(markdown: streamingText, isUser: false)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else if thinkFinished {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.vertical, 4)
                }
            }
            Spacer(minLength: 80)
        }
    }

    private var chatColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if !isSidebarExpanded, let onToggleSidebar {
                    NWPanelToggleButton(
                        role: .conversations,
                        isExpanded: false,
                        action: onToggleSidebar
                    )
                }
                Text(conversation.title?.isEmpty == false ? conversation.title! : "九木助手")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if previewDetail != nil {
                    NWStatusChip(text: "思考中…", tint: AppTheme.secondary)
                    Toggle("快速", isOn: .constant(true)).labelsHidden().controlSize(.mini)
                    Toggle("深度", isOn: .constant(false)).labelsHidden().controlSize(.mini)
                } else if isStreaming {
                    NWStatusChip(
                        text: statusChipText,
                        tint: AppTheme.secondary
                    )
                }
                if previewDetail == nil {
                    Button(role: .destructive) {
                        Task { await deleteCurrent() }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("删除对话")
                }
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
                        if previewDetail != nil {
                            agentDesignActionCallout
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
            VStack(alignment: .leading, spacing: 8) {
                if previewDetail == nil {
                    HStack(spacing: 10) {
                        Picker("回复模式", selection: $replyMode) {
                            ForEach(AgentReplyMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 220)
                        .disabled(isSending || isStreaming)
                        .onChange(of: replyMode) { _, mode in
                            mode.persist()
                        }
                        Text(replyMode == .fast ? "少推理，更快出结果" : "会先思考再回答")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }

                HStack(spacing: 12) {
                    if previewDetail != nil {
                        Image(systemName: "paperclip")
                            .foregroundStyle(.secondary)
                    }
                    TextField(
                        previewDetail != nil ? "输入你的问题，或使用 / 选择指令" : "向九木助手提问…",
                        text: $draft,
                        axis: .vertical
                    )
                        .lineLimit(1 ... 4)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await send() } }
                    if previewDetail != nil {
                        NWStatusChip(text: "已获审批访问", tint: AppTheme.openStatus)
                    }
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
            }
            .padding(12)
        }
    }

    private var agentDesignActionCallout: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.openStatus)
            VStack(alignment: .leading, spacing: 8) {
                Text("建议前往需求创建页继续完善草稿。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {} label: {
                    Text("前往需求创建 >")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(12)
        .background(AppTheme.softPrimary, in: RoundedRectangle(cornerRadius: 10))
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
                    Group {
                        if isUser {
                            NWMarkdownChatText(markdown: message.content, isUser: true)
                        } else {
                            NWMarkdownChatText(markdown: message.content, isUser: false)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, isUser ? 10 : 12)
                    .foregroundStyle(isUser ? .white : AppTheme.onSurface)
                    .background(isUser ? AppTheme.primary : AppTheme.bubbleIncoming)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            if !isUser { Spacer(minLength: 80) }
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && !isStreaming
    }

    private var statusChipText: String {
        if replyMode == .fast { return "快速回复中" }
        return streamingThink.isEmpty || thinkFinished ? "回复中" : "思考中"
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        let anchorId = isStreaming ? "__streaming__" : displayMessages.last?.id
        guard let anchorId else { return }
        withAnimation { proxy.scrollTo(anchorId, anchor: .bottom) }
    }

    private func loadDetail() async {
        if let previewDetail {
            detail = previewDetail
            replyMode = AgentReplyMode.from(thinkMode: previewDetail.thinkMode)
            applyInitialDraftIfNeeded()
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await session.agentService.getConversation(id: conversation.id)
            if let mode = detail?.thinkMode {
                replyMode = AgentReplyMode.from(thinkMode: mode)
            }
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
        if let existingDetail = detail {
            detail = AgentConversationDetailDTO(
                id: existingDetail.id,
                title: existingDetail.title,
                thinkMode: existingDetail.thinkMode,
                createdAt: existingDetail.createdAt,
                updatedAt: existingDetail.updatedAt,
                messages: existingDetail.messages + [userMessage]
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
                thinkMode: replyMode.thinkMode,
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
        if let navigation = AgentNavigationEvent.decode(event: event, data: data) {
            if !session.navigation.navigate(to: navigation.path) {
                let label = navigation.title ?? navigation.path
                streamingText += "\n\n> macOS 客户端暂不支持打开「\(label)」。\n"
            }
            return
        }

        if let pending = AgentPendingToolEvent.decode(event: event, data: data) {
            pendingTool = pending
            streamingText += "\n\n> 等待确认：\(pending.message)\n"
            return
        }

        let lowered = event.lowercased().replacingOccurrences(of: "-", with: "_")
        if lowered == "done" || lowered == "end" || lowered == "complete" {
            return
        }
        if lowered == "think_end" {
            thinkFinished = true
            return
        }
        if lowered == "error" {
            streamTask?.cancel()
            return
        }
        if lowered == "tool_pending" || lowered == "plan" {
            return
        }
        if lowered == "tool_result" {
            guard let jsonData = data.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            else { return }
            if let payload = obj["data"] as? [String: Any], payload["pending"] as? Bool == true {
                return
            }
            if let message = obj["message"] as? String, !message.isEmpty {
                streamingText += "\n\n> \(message)\n"
            }
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

    private func resolvePendingTool(approved: Bool) async {
        guard let pending = pendingTool, !isResolvingTool else { return }
        isResolvingTool = true
        defer { isResolvingTool = false }
        do {
            let result = try await session.agentService.approveTool(
                conversationId: conversation.id,
                toolCallId: pending.id,
                approved: approved
            )
            pendingTool = nil
            if let message = result.message, !message.isEmpty {
                streamingText += "\n\n> \(message)\n"
            } else if !approved {
                streamingText += "\n\n> 已拒绝执行「\(pending.name)」。\n"
            }
            await loadDetail()
            await refreshListItem()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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

enum AgentDesignPreviewFixtures {
    static let details: [String: AgentConversationDetailDTO] = {
        let conversations = [
            AgentConversationDetailDTO(
                id: "preview-agent-1",
                title: "需求规划与发布建议",
                thinkMode: true,
                createdAt: "2026-07-18T09:20:00Z",
                updatedAt: "2026-07-18T14:35:00Z",
                messages: [
                    AgentMessageDTO(id: "preview-agent-message-1", role: "user", content: "帮我规划一个用户研究类需求的发布流程。", createdAt: "2026-07-18T14:32:00Z"),
                    AgentMessageDTO(
                        id: "preview-agent-message-2",
                        role: "assistant",
                        content: "建议按以下步骤推进：\\n1. 明确研究目标与交付物\\n2. 设定预算与托管金额\\n3. 选择标签与认证要求\\n4. 预览需求卡并确认\\n5. 发布后跟进申请人\\n6. 接受申请并生成订单",
                        thinking: "先梳理需求发布的关键节点，再给出可执行顺序。",
                        createdAt: "2026-07-18T14:35:00Z"
                    )
                ]
            ),
            AgentConversationDetailDTO(
                id: "preview-agent-2",
                title: "发布需求草稿",
                thinkMode: false,
                createdAt: "2026-07-17T10:10:00Z",
                updatedAt: "2026-07-17T10:18:00Z",
                messages: [
                    AgentMessageDTO(id: "preview-agent-message-3", role: "user", content: "起草一个竞品体验报告需求。", createdAt: "2026-07-17T10:10:00Z"),
                    AgentMessageDTO(id: "preview-agent-message-4", role: "assistant", content: "草稿已整理好。发布属于写操作，我会在执行前显示确认卡。", createdAt: "2026-07-17T10:18:00Z")
                ]
            )
        ]
        return Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
    }()
}

private struct AgentToolResultsRail: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                railSection("当前引用的草稿") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("用户研究驱动的首页信息架构优化", systemImage: "doc.text")
                            .font(.caption.weight(.semibold))
                        Text("v0.3 · 更新于 10:35")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button("打开草稿 ↗") {}
                            .font(.caption)
                            .foregroundStyle(AppTheme.primary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(AppTheme.outlineVariant) }
                }

                railSection("工具结果") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("navigate_to")
                                .font(.caption.weight(.semibold).monospaced())
                            Spacer()
                            NWStatusChip(text: "成功", tint: AppTheme.openStatus)
                        }
                        toolRow("目标路径", "/demands/create")
                        toolRow("方法", "GET")
                        toolRow("时间", "10:42:18")
                        toolRow("结果", "已打开需求创建页")
                        Button("查看详情 ↗") {}
                            .font(.caption)
                            .foregroundStyle(AppTheme.primary)
                    }
                    .padding(12)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(AppTheme.outlineVariant) }
                }

                railSection("隐私与审批策略") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach([
                            "敏感数据仅在审批后访问",
                            "写操作需用户确认",
                            "工具调用保留审计记录",
                            "详细策略请参考《数据与隐私政策》"
                        ], id: \.self) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 4))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 5)
                                Text(line)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text("由 Ninewood 九木 提供")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                }
            }
            .padding(16)
        }
        .background(AppTheme.workspaceBackground)
    }

    private func railSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            content()
        }
    }

    private func toolRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption2)
        }
    }
}

private struct AgentToolApprovalSheet: View {
    let tool: AgentPendingToolEvent
    let isBusy: Bool
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("确认助手操作")
                .font(.title2.bold())
            Text(tool.message)
                .font(.body)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("工具：\(tool.name)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(tool.argumentsSummary)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.groupedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            HStack {
                Button("拒绝", role: .destructive, action: onReject)
                    .disabled(isBusy)
                Spacer()
                if isBusy {
                    ProgressView().controlSize(.small)
                }
                Button("允许执行", action: onApprove)
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)
            }
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 220)
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
