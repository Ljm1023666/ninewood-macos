import SwiftUI

struct AgentChatView: View {
    @Environment(AppSession.self) private var session
    var initialPrompt: String? = nil

    @AppStorage("agent.conversationSidebarExpanded") private var isSidebarExpanded = true
    @AppStorage(AgentAssistantMode.defaultsKey) private var assistantModeRaw = AgentAssistantMode.chat.rawValue
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
                        agentChromeBar(title: "九木助手", showModeSegment: true)
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
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Button {
                    Task { await loadConversations() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("刷新")
                Button {
                    Task { await createConversation() }
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("新对话")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

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
                    message: "点击右上角新建图标开始"
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

    private func agentChromeBar(title: String, showModeSegment: Bool = false) -> some View {
        HStack(spacing: 10) {
            if !isSidebarExpanded {
                NWPanelToggleButton(
                    role: .conversations,
                    isExpanded: false,
                    action: toggleSidebar
                )
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            if showModeSegment {
                AgentAssistantModeSegment(assistantModeRaw: $assistantModeRaw)
            }
            if showModeSegment {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.workspaceBackground)
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
            let mode = AgentAssistantMode.preferred()
            let model = AgentModelOption.preferred(for: mode)
            let created = try await session.agentService.createConversation(
                title: nil,
                thinkMode: AgentReplyMode.preferred(for: model).thinkMode
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

private enum AgentChatLayout {
    static let contentMaxWidth: CGFloat = 720
}

/// 助手顶层模式：Chat 日常对话 / Work 平台任务与工具。
private enum AgentAssistantMode: String, CaseIterable, Identifiable {
    case chat
    case work

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: return "Chat"
        case .work: return "Work"
        }
    }

    static let defaultsKey = "agent.assistantMode"
    static let chatModelKey = "agent.selectedChatModel"
    static let workModelKey = "agent.selectedWorkModel"

    static func preferred() -> AgentAssistantMode {
        if let saved = UserDefaults.standard.string(forKey: defaultsKey),
           let mode = AgentAssistantMode(rawValue: saved) {
            return mode
        }
        if let legacy = AgentModelOption.resolveLegacySaved() {
            return legacy.assistantMode
        }
        return .chat
    }

    func persist() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}

private struct AgentAssistantModeSegment: View {
    @Binding var assistantModeRaw: String

    private var assistantMode: AgentAssistantMode {
        AgentAssistantMode(rawValue: assistantModeRaw) ?? .chat
    }

    var body: some View {
        HStack(spacing: 0) {
            modePill(AgentAssistantMode.chat)
            modePill(AgentAssistantMode.work)
        }
        .frame(width: 168)
        .padding(3)
        .background(AppTheme.surfaceLow, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func modePill(_ mode: AgentAssistantMode) -> some View {
        Button {
            guard assistantMode != mode else { return }
            assistantModeRaw = mode.rawValue
            mode.persist()
            let model = AgentModelOption.preferred(for: mode)
            model.persist(for: mode)
        } label: {
            Text(mode.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(assistantMode == mode ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    assistantMode == mode ? AppTheme.primary : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help(mode == .chat ? "日常对话，不调用工作台工具" : "执行任务，可查找需求、导航与起草")
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

    /// 仅现网 35B 记忆深度偏好；其它模型不读此开关。
    static let defaultsKey = "agent.preferDeepThink"

    static func preferred(for model: AgentModelOption) -> AgentReplyMode {
        guard model.supportsThinkToggle else { return .fast }
        let deep = UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? false
        return deep ? .deep : .fast
    }

    static func from(thinkMode: Bool?, model: AgentModelOption) -> AgentReplyMode {
        guard model.supportsThinkToggle else { return .fast }
        return (thinkMode ?? false) ? .deep : .fast
    }

    func persist(for model: AgentModelOption) {
        guard model.supportsThinkToggle else { return }
        UserDefaults.standard.set(thinkMode, forKey: Self.defaultsKey)
    }
}

/// 助手对比用模型白名单（与实验室 `docs/OLLAMA-INSTALLED.md` 对齐）。
private enum AgentModelOption: String, CaseIterable, Identifiable {
    case production = "qwen3.6:35b"
    case ninewoodChat7b = "ninewood-chat-7b"
    case ninewoodChat15b = "ninewood-chat-1.5b"
    case ninewoodWork3b = "ninewood-work-3b"
    case qwen05b = "qwen2.5:0.5b"
    case qwen15b = "qwen2.5:1.5b"
    case qwen3b = "qwen2.5:3b"
    case qwenCoder15b = "qwen2.5-coder:1.5b"
    case llama32_1b = "llama3.2:1b"

    var id: String { rawValue }

    var ollamaName: String { rawValue }

    /// 仅现网大模型支持「快速 / 深度」；实验室小模型不分级。
    var supportsThinkToggle: Bool { self == .production }

    var shortTitle: String {
        switch self {
        case .production: return "现网 35B"
        case .ninewoodChat7b: return "九木 Chat 7B"
        case .ninewoodChat15b: return "九木 Chat 1.5B（对照）"
        case .ninewoodWork3b: return "九木 Work 3B"
        case .qwen05b: return "Qwen 0.5B"
        case .qwen15b: return "Qwen 1.5B"
        case .qwen3b: return "Qwen 3B"
        case .qwenCoder15b: return "Coder 1.5B"
        case .llama32_1b: return "Llama 1B"
        }
    }

    static let defaultsKey = "agent.selectedModel"

    /// 旧实验标签 → 当前 Work 导出名
    private static let legacyAliases: [String: AgentModelOption] = [
        "ninewood-3b-v3": .ninewoodWork3b,
        "ninewood-3b-v2.1": .ninewoodWork3b,
        "ninewood-3b-v2.1-f16": .ninewoodWork3b,
        "ninewood-3b-v2.1-q4": .ninewoodWork3b,
        "ninewood-chat-1.5b": .ninewoodChat7b,
    ]

    var assistantMode: AgentAssistantMode {
        switch self {
        case .ninewoodChat7b, .ninewoodChat15b:
            return .chat
        default:
            return .work
        }
    }

    static var chatModels: [AgentModelOption] {
        [.ninewoodChat7b, .ninewoodChat15b]
    }

    static var workModels: [AgentModelOption] {
        [.production, .ninewoodWork3b, .qwen05b, .qwen15b, .qwen3b, .qwenCoder15b, .llama32_1b]
    }

    static func models(for mode: AgentAssistantMode) -> [AgentModelOption] {
        mode == .chat ? chatModels : workModels
    }

    static func preferred() -> AgentModelOption {
        preferred(for: AgentAssistantMode.preferred())
    }

    static func preferred(for mode: AgentAssistantMode) -> AgentModelOption {
        let key = mode == .chat ? AgentAssistantMode.chatModelKey : AgentAssistantMode.workModelKey
        let saved = UserDefaults.standard.string(forKey: key) ?? ""
        if let option = AgentModelOption(rawValue: saved), option.assistantMode == mode {
            return option
        }
        if mode == .chat, let legacy = resolveLegacySaved(), legacy.assistantMode == .chat {
            legacy.persist(for: .chat)
            return legacy
        }
        if mode == .work, let legacy = resolveLegacySaved(), legacy.assistantMode == .work {
            legacy.persist(for: .work)
            return legacy
        }
        switch mode {
        case .chat: return .ninewoodChat7b
        case .work: return .ninewoodWork3b
        }
    }

    fileprivate static func resolveLegacySaved() -> AgentModelOption? {
        let saved = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        if let option = AgentModelOption(rawValue: saved) {
            return option
        }
        if let migrated = legacyAliases[saved] {
            return migrated
        }
        return nil
    }

    func persist() {
        persist(for: assistantMode)
    }

    func persist(for mode: AgentAssistantMode) {
        let key = mode == .chat ? AgentAssistantMode.chatModelKey : AgentAssistantMode.workModelKey
        UserDefaults.standard.set(rawValue, forKey: key)
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
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
    @AppStorage(AgentAssistantMode.defaultsKey) private var assistantModeRaw = AgentAssistantMode.chat.rawValue
    @State private var replyMode: AgentReplyMode = AgentReplyMode.preferred(
        for: AgentModelOption.preferred(for: AgentAssistantMode.preferred())
    )
    @State private var selectedModel: AgentModelOption = AgentModelOption.preferred(
        for: AgentAssistantMode.preferred()
    )
    @State private var isLoading = false
    @State private var isSending = false
    @State private var isStreaming = false
    @State private var streamingText = ""
    @State private var streamingThink = ""
    @State private var thinkFinished = false
    @State private var errorMessage: String?
    @State private var streamTask: Task<Void, Never>?
    @State private var streamReceivedChunks = false
    /// 本地已触发壳层跳转时，离开助手页不要掐断 SSE（否则服务端工具记录会丢）。
    @State private var retainStreamAcrossDisappear = false
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
            replyMode = AgentReplyMode.from(thinkMode: conversation.thinkMode, model: selectedModel)
            await loadDetail()
        }
        .onChange(of: initialDraft) { _, _ in
            applyInitialDraftIfNeeded()
        }
        .onDisappear {
            if !retainStreamAcrossDisappear {
                streamTask?.cancel()
            }
        }
        .onChange(of: assistantModeRaw) { _, newValue in
            let mode = AgentAssistantMode(rawValue: newValue) ?? .chat
            selectedModel = AgentModelOption.preferred(for: mode)
            replyMode = AgentReplyMode.preferred(for: selectedModel)
        }
        .onAppear {
            let mode = AgentAssistantMode(rawValue: assistantModeRaw) ?? .chat
            selectedModel = AgentModelOption.preferred(for: mode)
            replyMode = AgentReplyMode.preferred(for: selectedModel)
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
                onOpenPublishWorkspace: tool.name == "create_demand"
                    ? { Task { await openDemandWorkspaceFromPending(tool) } }
                    : nil,
                onApprove: { Task { await resolvePendingTool(approved: true) } },
                onReject: { Task { await resolvePendingTool(approved: false) } }
            )
        }
    }

    private var streamingBubble: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if !streamingThink.isEmpty {
                    AgentThinkingBlock(
                        text: streamingThink,
                        isLive: !thinkFinished,
                        initiallyExpanded: true
                    )
                }
                if !streamingText.isEmpty {
                    NWMarkdownChatText(markdown: streamingText, isUser: false)
                } else if thinkFinished {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if previewDetail == nil {
                    AgentAssistantModeSegment(assistantModeRaw: $assistantModeRaw)
                        .disabled(isSending || isStreaming)
                }
                Spacer(minLength: 0)
                if previewDetail != nil {
                    NWStatusChip(text: "预览", tint: AppTheme.secondary)
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
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("删除对话")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppTheme.workspaceBackground)

            ScrollViewReader { proxy in
                ScrollView {
                    // VStack：Markdown + fixedSize 在 LazyVStack 下易估高为 0，造成气泡重叠
                    VStack(alignment: .leading, spacing: 20) {
                        if isLoading && displayMessages.isEmpty && streamingText.isEmpty && streamingThink.isEmpty {
                            ProgressView().padding(.top, 40)
                                .frame(maxWidth: .infinity)
                        }
                        ForEach(displayMessages) { message in
                            agentBubble(message)
                                .id(message.id)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if previewDetail != nil {
                            agentDesignActionCallout
                        }
                        if isStreaming, !streamingThink.isEmpty || !streamingText.isEmpty {
                            streamingBubble
                                .id("__streaming__")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(maxWidth: AgentChatLayout.contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
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

            composerBar
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .frame(maxWidth: AgentChatLayout.contentMaxWidth)
                .frame(maxWidth: .infinity)
        }
        .background(AppTheme.workspaceBackground)
    }

    private var composerBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if selectedModel.supportsThinkToggle {
                    ForEach(AgentReplyMode.allCases) { mode in
                        Button {
                            guard previewDetail == nil else { return }
                            replyMode = mode
                            mode.persist(for: selectedModel)
                        } label: {
                            Text(mode.title)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    replyMode == mode ? AppTheme.softPrimary : Color.clear,
                                    in: Capsule(style: .continuous)
                                )
                                .foregroundStyle(replyMode == mode ? AppTheme.secondary : .secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSending || isStreaming || previewDetail != nil)
                    }
                }

                modelPickerChip
                    .disabled(isSending || isStreaming || previewDetail != nil)

                Spacer(minLength: 0)
                if previewDetail != nil {
                    NWStatusChip(text: "已获审批访问", tint: AppTheme.openStatus)
                } else {
                    Text("仅影响后续回复")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    composerPlaceholder,
                    text: $draft,
                    axis: .vertical
                )
                .lineLimit(1 ... 6)
                .textFieldStyle(.plain)
                .font(.body)
                .onSubmit { Task { await send() } }

                Button {
                    Task { await send() }
                } label: {
                    Group {
                        if isSending || isStreaming {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 28, height: 28)
                    .background(
                        canSend ? AppTheme.primary : AppTheme.fill,
                        in: Circle()
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help("发送")
            }
        }
        .padding(12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
    }

    private var assistantMode: AgentAssistantMode {
        AgentAssistantMode(rawValue: assistantModeRaw) ?? .chat
    }

    private var composerPlaceholder: String {
        if previewDetail != nil {
            return "输入你的问题，或使用 / 选择指令"
        }
        switch assistantMode {
        case .chat:
            return "向九木助手提问…"
        case .work:
            return "描述要执行的任务，例如查找需求、起草发布…"
        }
    }

    private var modelPickerChip: some View {
        Menu {
            ForEach(AgentModelOption.models(for: assistantMode)) { option in
                Button {
                    selectedModel = option
                    option.persist(for: assistantMode)
                    replyMode = AgentReplyMode.preferred(for: option)
                } label: {
                    if selectedModel == option {
                        Label(option.shortTitle + " · " + option.ollamaName, systemImage: "checkmark")
                    } else {
                        Text(option.shortTitle + " · " + option.ollamaName)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 10, weight: .semibold))
                Text(selectedModel.shortTitle)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                selectedModel == .production ? Color.clear : AppTheme.softPrimary,
                in: Capsule(style: .continuous)
            )
            .foregroundStyle(AppTheme.secondary)
        }
        .menuStyle(.borderlessButton)
        .help(assistantMode == .chat
            ? "切换 Chat 模型。切换后仅影响后续回复。"
            : "切换 Work 模型。切换后仅影响后续回复。")
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
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                .buttonStyle(.plain)
                .disabled(true)
                .help("设计预览占位；线上助手会给出可跳转路径")
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppTheme.softPrimary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func agentBubble(_ message: AgentMessageDTO) -> some View {
        let isUser = message.role.lowercased() == "user"
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 48) }
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
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppTheme.softPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(AppTheme.primary.opacity(0.22), lineWidth: 1)
                                }
                        } else {
                            NWMarkdownChatText(markdown: message.content, isUser: false)
                        }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if !isUser { Spacer(minLength: 48) }
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && !isStreaming
    }

    private var statusChipText: String {
        if !selectedModel.supportsThinkToggle || replyMode == .fast { return "快速回复中" }
        return streamingThink.isEmpty || thinkFinished ? "回复中" : "思考中"
    }

    private var effectiveThinkMode: Bool {
        selectedModel.supportsThinkToggle && replyMode.thinkMode
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        let anchorId = isStreaming ? "__streaming__" : displayMessages.last?.id
        guard let anchorId else { return }
        withAnimation { proxy.scrollTo(anchorId, anchor: .bottom) }
    }

    private func loadDetail() async {
        if let previewDetail {
            detail = previewDetail
            replyMode = AgentReplyMode.from(thinkMode: previewDetail.thinkMode, model: selectedModel)
            applyInitialDraftIfNeeded()
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await session.agentService.getConversation(id: conversation.id)
            if let mode = detail?.thinkMode {
                replyMode = AgentReplyMode.from(thinkMode: mode, model: selectedModel)
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

        // Work：打开/跳转类意图先切壳层页面，再后台走 SSE 记工具；避免「嘴上说跳转、人还在聊天页」。
        let mode = AgentAssistantMode(rawValue: assistantModeRaw) ?? .chat
        if mode == .work, Self.isSimpleGreeting(text) {
            appendLocalAssistantMessage("你好！我是九木助手，可以帮你搜索需求、打开页面，或在确认后协助发布与申请。")
            return
        }
        if mode == .work, let route = AgentNavigateIntent.resolve(message: text) {
            retainStreamAcrossDisappear = true
            Task { @MainActor in
                await streamOrFallback(text: text)
                retainStreamAcrossDisappear = false
            }
            if !session.navigation.navigate(to: route.path) {
                errorMessage = "macOS 客户端暂不支持打开「\(route.title)」。"
                retainStreamAcrossDisappear = false
            }
            return
        }

        retainStreamAcrossDisappear = false
        await streamOrFallback(text: text)
    }

    private static func isSimpleGreeting(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "！!。,.，"))
        return ["你好", "您好", "嗨", "hello", "hi"].contains(normalized)
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

    private func appendLocalAssistantMessage(_ text: String) {
        guard let existingDetail = detail else { return }
        detail = AgentConversationDetailDTO(
            id: existingDetail.id,
            title: existingDetail.title,
            thinkMode: existingDetail.thinkMode,
            createdAt: existingDetail.createdAt,
            updatedAt: existingDetail.updatedAt,
            messages: existingDetail.messages + [
                AgentMessageDTO(id: UUID().uuidString, role: "assistant", content: text)
            ]
        )
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
                thinkMode: effectiveThinkMode,
                model: selectedModel.ollamaName,
                onEvent: { event, data in
                    if event.lowercased() != "meta" {
                        streamReceivedChunks = true
                    }
                    handleStreamEvent(event: event, data: data)
                },
                onDone: {
                    isStreaming = false
                    finish(failed: false)
                },
                onError: { error in
                    isStreaming = false
                    streamingText = ""
                    streamingThink = ""
                    thinkFinished = false
                    errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                    finish(failed: true)
                }
            )
        }

        let completedText = streamingText
        if failed {
            if streamReceivedChunks {
                await loadDetail()
                await refreshListItem()
            } else {
                await sendNonStreamFallback(text: text)
            }
        } else {
            await loadDetail()
            ensureCompletedStreamVisible(completedText)
            await refreshListItem()
        }
        streamingText = ""
        streamingThink = ""
        thinkFinished = false
    }

    private func ensureCompletedStreamVisible(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastMessage = detail?.messages.last
        let hasVisibleAssistant = lastMessage?.role.lowercased() == "assistant"
            && !(lastMessage?.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        guard !trimmed.isEmpty,
              !hasVisibleAssistant,
              let current = detail
        else { return }

        detail = AgentConversationDetailDTO(
            id: current.id,
            title: current.title,
            thinkMode: current.thinkMode,
            createdAt: current.createdAt,
            updatedAt: current.updatedAt,
            messages: current.messages + [
                AgentMessageDTO(id: UUID().uuidString, role: "assistant", content: trimmed)
            ]
        )
    }

    private func handleStreamEvent(event: String, data: String) {
        if let forbidden = AgentForbiddenEvent.decode(event: event, data: data) {
            streamingText += "\n\n> \(forbidden.message)\n"
            if let fallback = forbidden.fallbackPage {
                _ = session.navigation.navigate(to: fallback)
            }
            return
        }

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
            if let jsonData = data.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let message = obj["message"] as? String, !message.isEmpty {
                streamingText += "\n\n> \(message)\n"
                errorMessage = message
            } else if !data.isEmpty {
                streamingText += "\n\n> \(data)\n"
                errorMessage = data
            }
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
        // 正式产品：create_demand 不应在聊天内静默写库；引导到需求卡工作区。
        if approved, pending.name == "create_demand" {
            await openDemandWorkspaceFromPending(pending)
            return
        }
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
            if approved, let path = result.data?.path, path.hasPrefix("/") {
                _ = session.navigation.navigate(to: path)
            }
            await loadDetail()
            await refreshListItem()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 把 create_demand 参数交给需求卡工作区；并拒绝云端静默执行。
    private func openDemandWorkspaceFromPending(_ pending: AgentPendingToolEvent) async {
        let args = pending.argumentValues
        let handoff = PublishDraftHandoff(
            kind: .demand,
            title: args["title"] ?? "",
            summary: "",
            description: args["description"] ?? args["content"] ?? "",
            category: args["category"] ?? "",
            expectedOutcome: args["expectedOutcome"] ?? args["expected_outcome"] ?? "",
            budgetMin: args["budget"] ?? args["minimumPrice"] ?? args["minPrice"] ?? "",
            budgetMax: args["expectedPrice"] ?? args["maxPrice"] ?? "",
            priceUnit: "",
            serviceType: args["serviceType"] ?? "",
            deliveryMode: "",
            regionHint: args["region"] ?? args["cityName"] ?? "",
            claims: [],
            source: "agent-create_demand"
        )
        retainStreamAcrossDisappear = true
        _ = session.handoffPublishDraft(handoff)
        // 拒绝聊天内写库，避免双写
        do {
            _ = try await session.agentService.approveTool(
                conversationId: conversation.id,
                toolCallId: pending.id,
                approved: false
            )
        } catch {
            // 交接优先；拒绝失败不阻断跳转
        }
        pendingTool = nil
        streamingText += "\n\n> 已打开需求卡工作区，请在页面确认后发布（助手不会静默提交）。\n"
        retainStreamAcrossDisappear = false
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
    var onOpenPublishWorkspace: (() -> Void)? = nil
    let onApprove: () -> Void
    let onReject: () -> Void

    private var isCreateDemand: Bool { tool.name == "create_demand" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isCreateDemand ? "转到需求卡工作区" : "确认助手操作")
                .font(.title2.bold())
            Text(
                isCreateDemand
                    ? "正式产品结构下，需求发布在专用页面完成。助手只会预填草稿，不会在聊天里静默提交。"
                    : tool.message
            )
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
                if isCreateDemand, let onOpenPublishWorkspace {
                    Button("打开需求卡工作区", action: onOpenPublishWorkspace)
                        .buttonStyle(.borderedProminent)
                        .disabled(isBusy)
                } else {
                    Button("允许执行", action: onApprove)
                        .buttonStyle(.borderedProminent)
                        .disabled(isBusy)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 220)
    }
}

/// Codex 风格：克制可折叠思考过程
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
                HStack(spacing: 5) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                    Text(isLive ? "Thinking…" : "Thought")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isLive {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.leading, 15)
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
