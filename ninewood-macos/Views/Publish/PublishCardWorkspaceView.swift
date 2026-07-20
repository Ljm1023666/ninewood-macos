import SwiftUI

/// 对齐 Windows `DemandCreate`：左聊天（agent-demand-stream）+ 右结构化字段。
struct PublishCardWorkspaceView: View {
    enum Mode {
        case demand
        case service

        var title: String {
            switch self {
            case .demand: "需求工作区"
            case .service: "服务卡工作区"
            }
        }

        var aiMode: PublishAICardMode {
            switch self {
            case .demand: .demand
            case .service: .service
            }
        }

        var composerPlaceholder: String {
            switch self {
            case .demand: "说点什么？"
            case .service: "介绍你能提供的服务…"
            }
        }

        var emptyHint: String {
            switch self {
            case .demand: "在左侧描述你的需求，AI 会同步整理到这里"
            case .service: "在左侧介绍你的服务，AI 会同步整理到这里"
            }
        }
    }

    @Environment(AppSession.self) private var session
    let mode: Mode
    var frontendPreview: Bool = false

    @State private var messages: [PublishWorkspaceChatMessage] = []
    @State private var fields = PublishWorkspaceFields()
    @State private var lockedFields: Set<String> = []
    @State private var lockedKeywords: Set<String> = []
    @State private var expandedMessageIds: Set<String> = []
    @State private var missingQueue = PublishMissingQueueState()
    @State private var draftInput = ""
    @State private var isLoading = false
    @State private var speedMode = false
    @State private var thinkMode = false
    @State private var canvasMode = false
    @State private var thinkText = ""
    @State private var thinkCollapsed = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var confirmClear = false
    @State private var showConfirmPublish = false
    @State private var confirmPaths: [String] = []
    @State private var isPublishing = false
    @State private var streamTask: Task<Void, Never>?
    @State private var regions: [RegionDTO] = []
    @State private var activeSessionId: String?
    @State private var sessions: [PublishWorkspaceSessionSnapshot] = []
    @State private var persistTask: Task<Void, Never>?
    @FocusState private var composerFocused: Bool

    private var workspaceKind: PublishWorkspaceKind {
        mode == .service ? .service : .demand
    }

    private var isReady: Bool {
        if mode == .demand {
            return fields.validateForDemandPublish().isEmpty
        }
        return fields.validateForServicePublish().isEmpty
    }

    private var showRightContent: Bool {
        !messages.isEmpty || fields.hasCoreContent
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            GeometryReader { geo in
                let chatWidth = max(320, geo.size.width * 0.42)
                HStack(spacing: 0) {
                    chatColumn
                        .frame(width: chatWidth)
                    Divider().opacity(0.5)
                    workspaceColumn
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color.white)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(mode == .demand ? "publish-workspace-demand" : "publish-workspace-service")
        .onAppear {
            restoreOrCreateSession()
            consumeHandoff()
            composerFocused = true
            Task { await loadRegions() }
        }
        .onDisappear {
            streamTask?.cancel()
            persistActiveSession()
        }
        .onChange(of: messages) { _, _ in schedulePersist() }
        .onChange(of: fields) { _, _ in schedulePersist() }
        .onChange(of: draftInput) { _, _ in schedulePersist() }
        .onChange(of: missingQueue) { _, _ in schedulePersist() }
        .alert("提示", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("确定要清空当前所有内容吗？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空并新建", role: .destructive) { startNewSession() }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showConfirmPublish) {
            PublishConfirmPathsSheet(
                fields: fields,
                regionName: regions.first(where: { $0.id == fields.regionId })?.name,
                isService: mode == .service,
                autoPaths: fields.derivedPaths,
                paths: $confirmPaths,
                isPublishing: isPublishing,
                onBack: { showConfirmPublish = false },
                onConfirm: {
                    Task { await commitPublishFromConfirm() }
                }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                _ = session.navigation.navigate(to: "/publish")
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help("返回发布工作台")
            .accessibilityLabel("返回发布工作台")
            .accessibilityIdentifier("publish-ws-back")

            Text(mode.title)
                .font(.system(size: 16, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("publish-ws-title")

            Spacer()

            PublishSessionMenu(
                sessions: sessions,
                activeId: activeSessionId,
                onSelect: loadSession,
                onDelete: deleteSession
            )
            .accessibilityIdentifier("publish-ws-history")

            Button {
                if !messages.isEmpty || fields.hasCoreContent {
                    confirmClear = true
                } else {
                    startNewSession()
                }
            } label: {
                Label("新建", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("新建")
            .accessibilityIdentifier("publish-ws-new")

            if !fields.title.isEmpty {
                Text(confidenceLabel)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(confidenceColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(confidenceColor)
                    .accessibilityLabel(confidenceLabel)
            }

            Button {
                beginPublishFlow()
            } label: {
                Text(mode == .service ? "保存草稿" : "发布")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isReady || isLoading || isPublishing)
            .controlSize(.small)
            .accessibilityLabel(mode == .service ? "保存草稿" : "发布")
            .accessibilityIdentifier("publish-ws-publish")
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            if let successMessage {
                Text(successMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.openStatus)
                    .padding(.bottom, 4)
            }
        }
    }

    private var confidenceLabel: String {
        switch fields.confidence.lowercased() {
        case "high": "置信度高"
        case "medium": "置信度中"
        default: "置信度低"
        }
    }

    private var confidenceColor: Color {
        switch fields.confidence.lowercased() {
        case "high": .green
        case "medium": .orange
        default: .red
        }
    }

    // MARK: - Chat (left 42%)

    private var chatColumn: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if messages.isEmpty {
                            chatEmpty
                        }
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
                            chatBubble(msg, isLast: index == messages.count - 1)
                                .id(msg.id)
                        }
                        if isLoading, !(messages.last?.isStreaming ?? false) {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("AI 分析中…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last?.id {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 8) {
                if thinkMode, (!thinkText.isEmpty || isLoading) {
                    thinkingPanel
                }
                composer
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var chatEmpty: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.2, green: 0.53, blue: 1.0).opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(red: 0.2, green: 0.53, blue: 1.0))
            }
            Text(mode == .service ? "介绍你的服务，我来帮你整理成服务卡" : "描述你的需求，我来帮你整理成需求卡")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(nsColor: .labelColor))
                .multilineTextAlignment(.center)
            Text("Speed 一句话成稿 · Think 看推理 · Canvas 预览卡片")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }

    private func chatBubble(_ msg: PublishWorkspaceChatMessage, isLast: Bool) -> some View {
        let isUser = msg.role == "user"
        let collapsed = !isUser && !msg.isStreaming && !isLast && !expandedMessageIds.contains(msg.id)

        return VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
            if collapsed {
                Button {
                    expandedMessageIds.insert(msg.id)
                } label: {
                    Text(collapsedPreview(msg.content))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7), in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                if !isUser, !isLast, !msg.isStreaming {
                    Button("收起 ↑") {
                        expandedMessageIds.remove(msg.id)
                    }
                    .font(.caption2)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }

                Group {
                    if msg.isStreaming && msg.content.isEmpty {
                        Text("填写中...")
                            .font(.callout.italic())
                            .foregroundStyle(.secondary)
                    } else if isUser {
                        Text(msg.content)
                            .font(.callout)
                            .textSelection(.enabled)
                    } else {
                        HStack(alignment: .bottom, spacing: 2) {
                            NWMarkdownChatText(markdown: msg.content, isUser: false)
                            if msg.isStreaming {
                                Circle()
                                    .fill(Color(red: 0.2, green: 0.53, blue: 1.0))
                                    .frame(width: 6, height: 6)
                                    .padding(.bottom, 4)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    isUser
                        ? Color(nsColor: .controlBackgroundColor)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

                if let args = msg.toolArgs, !args.isEmpty {
                    toolConfirmCard(args)
                }
            }
        }
    }

    private func collapsedPreview(_ content: String) -> String {
        let t = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= 80 { return t }
        return String(t.prefix(80)) + "…"
    }

    private func toolConfirmCard(_ args: [String: String]) -> some View {
        let ready = isReady
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(ready ? Color(red: 0.02, green: 0.59, blue: 0.41) : .orange)
                Text(ready
                     ? (mode == .service ? "信息已齐备，可以发布服务卡" : "信息已齐备，可以发布")
                     : "AI 已提取部分信息，请补全后发布")
                    .font(.caption.weight(.semibold))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                if let t = args["title"] { kv("标题", t) }
                if let st = args["serviceType"] {
                    kv("服务类型", st == "OFFLINE" ? "线下" : "线上")
                }
                if let c = args["category"] { kv("分类", c) }
                if let b = args["budget"] {
                    kv(mode == .service ? "报价" : "预算", b)
                }
                if let s = args["schedule"] {
                    kv(mode == .service ? "交付" : "时间", s)
                }
            }
            if let d = args["description"], !d.isEmpty {
                kv(mode == .service ? "服务说明" : "详细描述", d)
            }
            Button {
                handlePublishFromChat(args)
            } label: {
                Label("确认发布", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08))
        }
    }

    private func kv(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.tertiary)
            Text(value).font(.caption).lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var thinkingPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                thinkCollapsed.toggle()
            } label: {
                HStack {
                    Image(systemName: "brain")
                    Text("思考过程")
                    if isLoading {
                        ProgressView().controlSize(.mini)
                    }
                    Spacer()
                    Image(systemName: thinkCollapsed ? "chevron.down" : "chevron.up")
                }
                .font(.caption)
                .foregroundStyle(Color(red: 0.49, green: 0.23, blue: 0.93))
            }
            .buttonStyle(.plain)
            if !thinkCollapsed {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(thinkText.isEmpty ? "思考中…" : thinkText)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Color(red: 0.49, green: 0.23, blue: 0.93))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("think-end")
                    }
                    .frame(maxHeight: 120)
                    .padding(8)
                    .background(Color(red: 0.49, green: 0.23, blue: 0.93).opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color(red: 0.49, green: 0.23, blue: 0.93).opacity(0.18))
                    }
                    .onChange(of: thinkText) { _, _ in
                        withAnimation { proxy.scrollTo("think-end", anchor: .bottom) }
                    }
                }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                modeChip("bolt.fill", "Speed", active: speedMode) {
                    speedMode.toggle()
                    if speedMode { thinkMode = false; canvasMode = false }
                }
                modeChip("brain", "Think", active: thinkMode) {
                    thinkMode.toggle()
                    if thinkMode { speedMode = false; canvasMode = false }
                }
                modeChip("rectangle.on.rectangle", "Canvas", active: canvasMode) {
                    canvasMode.toggle()
                    if canvasMode { speedMode = false; thinkMode = false }
                }
                Spacer()
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField(
                    missingQueue.missingQueue.isEmpty ? mode.composerPlaceholder : "回答当前待补充问题…",
                    text: $draftInput,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .lineLimit(1 ... 5)
                .focused($composerFocused)
                .accessibilityLabel("发布整理输入框")
                .accessibilityIdentifier("publish-ws-composer")
                // 多行 TextField 默认 Return 换行；与 Windows 一致：Return 发送，Shift+Return 换行
                .onKeyPress(keys: [.return]) { press in
                    if press.modifiers.contains(.shift) {
                        return .ignored
                    }
                    sendCurrent()
                    return .handled
                }

                Button {
                    if isLoading {
                        abortStreaming()
                    } else {
                        sendCurrent()
                    }
                } label: {
                    Image(systemName: isLoading ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(
                            isLoading
                                ? Color.primary
                                : (canSend ? Color(red: 0.2, green: 0.53, blue: 1.0) : Color.secondary.opacity(0.35))
                        )
                        .accessibilityHidden(true)
                }
                .buttonStyle(.plain)
                .disabled(!isLoading && !canSend)
                .help(isLoading ? "停止" : "发送")
                .accessibilityElement()
                .accessibilityLabel(isLoading ? "停止" : "发送")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier(isLoading ? "publish-ws-stop" : "publish-ws-send")
                .accessibilityValue(canSend || isLoading ? "enabled" : "disabled")
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06))
            }
        }
    }

    private func modeChip(_ systemImage: String, _ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                active ? Color(red: 0.2, green: 0.53, blue: 1.0).opacity(0.14) : Color(nsColor: .controlBackgroundColor),
                in: Capsule()
            )
            .foregroundStyle(active ? Color(red: 0.2, green: 0.53, blue: 1.0) : .secondary)
            .overlay {
                Capsule().strokeBorder(active ? Color(red: 0.2, green: 0.53, blue: 1.0).opacity(0.35) : Color.black.opacity(0.06))
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(title)
        .accessibilityIdentifier("publish-ws-mode-\(title.lowercased())")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func abortStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isLoading = false
        thinkText = ""
        thinkMode = false
        finishStreamingFlags()
        messages.append(.init(id: UUID().uuidString, role: "assistant", content: "⏹ 已中断"))
    }

    private var canSend: Bool {
        !isLoading && !draftInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Workspace (right)

    private var workspaceColumn: some View {
        Group {
            if canvasMode {
                PublishCanvasCardPreview(fields: fields, isService: mode == .service)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.25))
            } else {
                ScrollView {
                    Group {
                        if showRightContent {
                            VStack(alignment: .leading, spacing: 20) {
                                summarySection
                                fieldsSection
                                PublishWorkspaceToolsPanel(
                                    fields: $fields,
                                    lockedFields: $lockedFields,
                                    queue: $missingQueue,
                                    mode: mode.aiMode,
                                    frontendPreview: frontendPreview,
                                    apiClient: session.apiClient,
                                    onAskCurrent: { item in
                                        messages.append(.init(
                                            id: UUID().uuidString,
                                            role: "assistant",
                                            content: "请补充：\(item)"
                                        ))
                                    }
                                )
                            }
                            .padding(20)
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 20))
                                    .foregroundStyle(AppTheme.primary)
                                Text(mode.emptyHint)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, minHeight: 280)
                            .padding(40)
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.25))
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(mode == .service ? "服务摘要" : "需求摘要")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            fieldRow(lockKey: "title") {
                TextField(mode == .service ? "服务标题（AI 自动生成）" : "需求标题（AI 自动生成）", text: Binding(
                    get: { fields.title },
                    set: { fields.title = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("publish-ws-field-title")
            }

            fieldRow(lockKey: "description") {
                TextEditor(text: Binding(
                    get: { fields.description },
                    set: { fields.description = $0 }
                ))
                .font(.body)
                .frame(minHeight: 100)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(AppTheme.outlineVariant)
                }
            }
        }
    }

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("结构化信息")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            fieldRow(lockKey: "serviceType") {
                HStack(spacing: 8) {
                    segButton("线上", selected: fields.serviceType == "ONLINE") {
                        fields.serviceType = "ONLINE"
                    }
                    segButton("线下", selected: fields.serviceType == "OFFLINE") {
                        fields.serviceType = "OFFLINE"
                    }
                }
            }

            fieldRow(lockKey: "regionId") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(fields.serviceType == "OFFLINE" ? "服务地区（线下必填）" : "服务地区（可选）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Picker("地区", selection: Binding(
                        get: { fields.regionId ?? -1 },
                        set: { fields.regionId = $0 < 0 ? nil : $0 }
                    )) {
                        Text("不限").tag(-1)
                        ForEach(regions) { region in
                            Text(region.name ?? "地区 \(region.id)").tag(region.id)
                        }
                    }
                    .labelsHidden()
                }
            }

            HStack(alignment: .top, spacing: 12) {
                fieldRow(lockKey: "budget") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mode == .service ? "报价" : "预算")
                            .font(.caption2).foregroundStyle(.secondary)
                        TextField(mode == .service ? "如 300-500元/次" : "如 30-50元/局", text: Binding(
                            get: { fields.budget },
                            set: { fields.budget = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }
                fieldRow(lockKey: "schedule") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mode == .service ? "交付方式" : "时间")
                            .font(.caption2).foregroundStyle(.secondary)
                        TextField(mode == .service ? "如 线上交付 / 3天内" : "如 今晚", text: Binding(
                            get: { fields.schedule },
                            set: { fields.schedule = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }
            }

            fieldRow(lockKey: "category") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("分类").font(.caption2).foregroundStyle(.secondary)
                    TextField(mode == .service ? "如 编程/网站开发" : "如 游戏/陪玩/代打", text: Binding(
                        get: { fields.category },
                        set: { fields.category = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    if !fields.scopeLabels.isEmpty {
                        FlowTags(tags: fields.scopeLabels)
                    }
                }
            }

            if !fields.suggestedKeywords.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("关键词（点击锁定）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(fields.suggestedKeywords, id: \.self) { kw in
                            let locked = lockedKeywords.contains(kw)
                            Button {
                                if locked { lockedKeywords.remove(kw) } else { lockedKeywords.insert(kw) }
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: locked ? "lock.fill" : "tag")
                                        .font(.caption2)
                                    Text(kw).font(.caption2)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    locked ? Color(red: 0.2, green: 0.53, blue: 1.0).opacity(0.14) : AppTheme.fill.opacity(0.4),
                                    in: Capsule()
                                )
                                .foregroundStyle(locked ? Color(red: 0.2, green: 0.53, blue: 1.0) : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            fieldRow(lockKey: "expectedOutcome") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode == .service ? "服务范围补充" : "预期效果")
                        .font(.caption2).foregroundStyle(.secondary)
                    TextField(
                        mode == .service ? "如：包含设计、开发和上线协助" : "如：星耀二上王者",
                        text: Binding(
                            get: { fields.expectedOutcome },
                            set: { fields.expectedOutcome = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                }
            }

            if mode == .demand {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("公开窗口 (分钟)").font(.caption2).foregroundStyle(.secondary)
                        TextField("15", value: Binding(
                            get: { fields.visibilityWindow },
                            set: { fields.visibilityWindow = min(1440, max(1, $0)) }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("接单上限").font(.caption2).foregroundStyle(.secondary)
                        TextField("10", value: Binding(
                            get: { fields.maxApplicants },
                            set: { fields.maxApplicants = min(100, max(1, $0)) }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("服务时限（分钟，可选）").font(.caption2).foregroundStyle(.secondary)
                TextField(
                    "如 60",
                    value: Binding(
                        get: { fields.timeLimitMinutes ?? 0 },
                        set: { fields.timeLimitMinutes = $0 <= 0 ? nil : min(10080, max(15, $0)) }
                    ),
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                Text("可选；到期后平台会提醒双方确认进度，不会自动扣款")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func fieldRow<Content: View>(lockKey: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 8) {
            content()
            Toggle("", isOn: Binding(
                get: { lockedFields.contains(lockKey) },
                set: { on in
                    if on { lockedFields.insert(lockKey) } else { lockedFields.remove(lockKey) }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.mini)
            .help(lockedFields.contains(lockKey) ? "已锁定，AI 不再覆盖" : "锁定字段")
            .padding(.top, 4)
        }
    }

    private func segButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? AppTheme.softPrimary : AppTheme.fill.opacity(0.35), in: Capsule())
                .foregroundStyle(selected ? AppTheme.primary : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func sendCurrent() {
        let text = draftInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }
        draftInput = ""
        messages.append(.init(id: UUID().uuidString, role: "user", content: text))
        Task { await runAI(userText: text) }
    }

    @MainActor
    private func runAI(userText: String) async {
        isLoading = true
        thinkText = ""
        errorMessage = nil
        defer { isLoading = false }

        if frontendPreview {
            applyPreview(userText)
            return
        }

        // Windows：若有 missingQueue，先记答案；全部答完再批量 analyze
        if !missingQueue.missingQueue.isEmpty {
            let allDone = missingQueue.recordAnswerAndAdvance(userText)
            if allDone {
                await runMissingBatchAnalysis()
            } else {
                let remain = missingQueue.missingQueue.count
                let next = missingQueue.missingQueue.first.map { "请继续回答：\($0)" } ?? ""
                messages.append(.init(
                    id: UUID().uuidString,
                    role: "assistant",
                    content: "已记录。还剩 \(remain) 项。\(next)"
                ))
            }
            return
        }

        if canvasMode {
            await runCanvas(text: userText)
            return
        }

        if speedMode {
            await runSpeed(text: userText)
            return
        }

        await runAgentStream(userText: userText, think: thinkMode)
    }

    @MainActor
    private func runMissingBatchAnalysis() async {
        let qa = missingQueue.answeredQueue.map { q in
            "问：\(q)\n答：\(missingQueue.missingAnswers[q] ?? "(未提供)")"
        }.joined(separator: "\n\n")
        let confirmed = fields.confirmedContext(locked: lockedFields, lockedKeywords: lockedKeywords)
        let prompt = "用户针对以下问题逐一提供了答案：\n\n\(qa)\n\n\(confirmed.isEmpty ? "" : "已确认的上下文：\(confirmed)\n")请整合所有新信息，更新需求分析。"
        do {
            let result = try await PublishAIService(client: session.apiClient)
                .analyzeDemandLongTimeout(text: prompt, mode: mode.aiMode)
            fields.applyAnalyze(result, locked: lockedFields)
            missingQueue.resolveAllAnswered()
            messages.append(.init(
                id: UUID().uuidString,
                role: "assistant",
                content: "已综合所有回答更新工作区。"
            ))
        } catch {
            missingQueue.resolveAllAnswered()
            messages.append(.init(
                id: UUID().uuidString,
                role: "assistant",
                content: (error as? LocalizedError)?.errorDescription ?? "网络异常"
            ))
        }
    }

    @MainActor
    private func runCanvas(text: String) async {
        let assistantId = UUID().uuidString
        messages.append(.init(id: assistantId, role: "assistant", content: "Canvas 分析中…", isStreaming: true))
        let history: [PublishAgentChatMessage] = [
            .init(role: "user", content: text, reasoningContent: nil),
        ]
        do {
            let result = try await PublishAIService(client: session.apiClient)
                .syncAnalyzeFromConversation(
                    messages: history,
                    mode: mode.aiMode,
                    requirementState: fields.requirementState(locked: lockedFields)
                )
            fields.applyAnalyze(result, locked: lockedFields)
            if let title = result.title, !title.isEmpty {
                lockedFields.insert("title")
            }
            let ready = isReady
            let body: String
            if let summary = result.summary, !summary.isEmpty {
                body = summary
            } else {
                body = "已分析\(mode == .service ? "服务卡" : "需求")"
            }
            let suffix: String
            if let missing = result.missingInfo, !missing.isEmpty {
                suffix = "\n\n还需补充：\(missing.joined(separator: "、"))"
            } else if ready {
                suffix = "\n\n信息完整，可以发布"
            } else {
                suffix = "\n\n请先在右侧工作区补全必填项"
            }
            if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                messages[idx].content = body + suffix
                messages[idx].isStreaming = false
            }
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                messages[idx].content = (error as? LocalizedError)?.errorDescription ?? "分析异常，请重试"
                messages[idx].isStreaming = false
            }
        }
    }

    /// Windows `sendMessage`：history 含 reasoning_content；末条 user 可带 confirmedCtx。
    @MainActor
    private func buildAgentHistory(augmentedUserText: String) -> [PublishAgentChatMessage] {
        var history: [PublishAgentChatMessage] = []
        // 除最后一条刚追加的 user 外，保留历史（含 assistant reasoning）
        let prior = messages.dropLast()
        for msg in prior where msg.role == "user" || msg.role == "assistant" {
            history.append(.init(
                role: msg.role,
                content: msg.content,
                reasoningContent: msg.reasoningContent
            ))
        }
        history.append(.init(role: "user", content: augmentedUserText, reasoningContent: nil))
        return history
    }

    @MainActor
    private func runSpeed(text: String) async {
        let assistantId = UUID().uuidString
        messages.append(.init(id: assistantId, role: "assistant", content: "", isStreaming: true))
        do {
            // Windows Speed → analyze-demand；macOS 用长超时，避免 15s 砍流
            let result = try await PublishAIService(client: session.apiClient)
                .analyzeDemandLongTimeout(text: text, mode: mode.aiMode)
            fields.applyAnalyze(result, locked: lockedFields)
            if speedMode, !fields.suggestedKeywords.isEmpty {
                lockedKeywords.formUnion(fields.suggestedKeywords)
            }
            let note = [
                result.title.map { "标题：\($0)" },
                result.category.map { "分类：\($0)" },
                result.budget.map { "\(mode == .service ? "报价" : "预算")：\($0)" },
            ].compactMap { $0 }.joined(separator: " · ")
            if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                messages[idx].content = note.isEmpty ? "已整理到右侧工作区，请核对后发布。" : note
                messages[idx].isStreaming = false
            }
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                messages[idx].content = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                messages[idx].isStreaming = false
            }
        }
    }

    @MainActor
    private func runAgentStream(userText: String, think: Bool) async {
        let confirmedCtx = fields.confirmedContext(locked: lockedFields, lockedKeywords: lockedKeywords)
        let augmented = confirmedCtx.isEmpty ? userText : "\(confirmedCtx)\n\(userText)"
        let history = buildAgentHistory(augmentedUserText: augmented)
        let reqState = fields.requirementState(locked: lockedFields)

        let assistantId = UUID().uuidString
        var assistantContent = ""
        var hasAssistant = false
        var pendingArgs: [String: String] = [:]
        var thinkAcc = ""
        let service = PublishAIService(client: session.apiClient)

        // 先按用户明确输入生成一个可编辑草稿；结构化服务成功后再覆盖优化。
        // 这样生产 AI 暂时不可用时，用户仍能在右侧核对并继续完成发布。
        fields.seedFromUserText(
            userText,
            serviceCard: mode == .service,
            regions: regions,
            locked: lockedFields
        )

        // 对齐 Windows syncWorkspaceFromConversation，但必须保留并等待结果。
        // 旧实现把同步丢进无人等待的 Task，主对话流结束后即使同步失败也会
        // 显示“已同步到右侧”，造成右侧字段全空的假成功。
        let workspaceSync = Task<PublishAnalyzeResult, Error> {
            do {
                return try await service.syncAnalyzeFromConversation(
                    messages: history,
                    mode: mode.aiMode,
                    requirementState: reqState
                )
            } catch {
                // 与 Windows Speed 使用同一结构化接口作为降级，避免某个 SSE
                // 代理只返回 agent 文本、却没有 result 事件时工作区永远为空。
                let transcript = history
                    .filter { $0.role == "user" }
                    .map(\.content)
                    .joined(separator: "\n")
                return try await service.analyzeDemandLongTimeout(
                    text: transcript,
                    mode: mode.aiMode
                )
            }
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var resumed = false
            let resumeOnce = {
                guard !resumed else { return }
                resumed = true
                cont.resume()
            }
            streamTask = service.streamAgentDemand(
                messages: history,
                mode: mode.aiMode,
                thinkMode: think,
                onEvent: { event, obj in
                    Task { @MainActor in
                        switch event {
                        case "think":
                            if think, let line = obj["line"] as? String {
                                thinkAcc += line
                                thinkText = thinkAcc
                            }
                        case "text":
                            if let delta = obj["delta"] as? String {
                                assistantContent += delta
                                if !hasAssistant {
                                    hasAssistant = true
                                    messages.append(.init(
                                        id: assistantId,
                                        role: "assistant",
                                        content: assistantContent,
                                        isStreaming: true
                                    ))
                                } else if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                                    messages[idx].content = assistantContent
                                }
                            }
                        case "tool_call":
                            if let args = obj["arguments"] as? [String: Any] {
                                for (k, v) in args {
                                    pendingArgs[k] = "\(v)"
                                }
                            }
                        case "error":
                            let msg = (obj["message"] as? String) ?? "AI 错误"
                            messages.append(.init(id: UUID().uuidString, role: "assistant", content: msg))
                        default:
                            break
                        }
                    }
                },
                onDone: {
                    Task { @MainActor in
                        if !pendingArgs.isEmpty {
                            fields.applyAgentArgs(pendingArgs, locked: lockedFields)
                        }
                        let reasoning = think && !thinkAcc.isEmpty ? thinkAcc : nil
                        if hasAssistant, let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                            messages[idx].isStreaming = false
                            messages[idx].reasoningContent = reasoning
                            if messages[idx].content.isEmpty {
                                messages[idx].content = pendingArgs.isEmpty
                                    ? "正在同步到右侧工作区…"
                                    : "已收集完整信息，准备发布"
                            }
                            if !pendingArgs.isEmpty {
                                messages[idx].toolArgs = pendingArgs
                            }
                        } else if !pendingArgs.isEmpty {
                            messages.append(.init(
                                id: assistantId,
                                role: "assistant",
                                content: "已收集完整信息，准备发布",
                                toolArgs: pendingArgs,
                                reasoningContent: reasoning
                            ))
                        } else if !hasAssistant {
                            messages.append(.init(
                                id: assistantId,
                                role: "assistant",
                                content: pendingArgs.isEmpty
                                    ? "正在同步到右侧工作区…"
                                    : "已收集完整信息，准备发布",
                                toolArgs: pendingArgs.isEmpty ? nil : pendingArgs,
                                reasoningContent: reasoning
                            ))
                        }
                        resumeOnce()
                    }
                },
                onError: { error in
                    Task { @MainActor in
                        messages.append(.init(
                            id: UUID().uuidString,
                            role: "assistant",
                            content: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        ))
                        resumeOnce()
                    }
                }
            )
        }

        do {
            let result = try await workspaceSync.value
            fields.applyAnalyze(result, locked: lockedFields)
            if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                if pendingArgs.isEmpty {
                    messages[idx].content = fields.hasCoreContent
                        ? "已同步到右侧，请继续补充或发布。"
                        : "已收到分析结果，但仍缺少标题或描述，请继续补充。"
                }
            } else {
                messages.append(.init(
                    id: assistantId,
                    role: "assistant",
                    content: fields.hasCoreContent
                        ? "已同步到右侧，请继续补充或发布。"
                        : "已收到分析结果，但仍缺少标题或描述，请继续补充。"
                ))
            }
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == assistantId }),
               messages[idx].content == "正在同步到右侧工作区…" {
                messages[idx].content = fields.hasCoreContent
                    ? "已按你的原文填入右侧；AI 优化暂时不可用，请核对字段。"
                    : "工作区同步失败，请重试。"
            } else {
                messages.append(.init(
                    id: UUID().uuidString,
                    role: "assistant",
                    content: fields.hasCoreContent
                        ? "已按你的原文填入右侧；AI 优化暂时不可用，请核对字段。"
                        : "工作区同步失败，请重试。"
                ))
            }
            if !fields.hasCoreContent {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        streamTask = nil
    }

    private func applyPreview(_ text: String) {
        // 设计预览 / 离线：本地 seed + 结构化草稿，保证右侧立刻有内容
        fields.seedFromUserText(
            text,
            serviceCard: mode == .service,
            regions: regions,
            locked: lockedFields
        )
        if !lockedFields.contains("title"), fields.title.isEmpty {
            fields.title = String(text.prefix(24))
        }
        if !lockedFields.contains("description"), fields.description.isEmpty {
            fields.description = text
        }
        if !lockedFields.contains("category"), fields.category.isEmpty {
            fields.category = "日常服务"
        }
        if !lockedFields.contains("budget"), fields.budget.isEmpty {
            fields.budget = "200-500"
        }
        if !lockedFields.contains("serviceType"), fields.serviceType == nil {
            fields.serviceType = text.contains("线下") || text.lowercased().contains("offline") ? "OFFLINE" : "ONLINE"
        }
        if !lockedFields.contains("schedule"), fields.schedule.isEmpty {
            fields.schedule = mode == .service ? "按双方约定" : "尽快"
        }
        fields.confidence = "medium"
        fields.readyToPublish = mode == .service ? fields.isServiceReady : fields.isDemandReady
        if speedMode, !fields.suggestedKeywords.isEmpty {
            lockedKeywords.formUnion(fields.suggestedKeywords)
        } else if fields.suggestedKeywords.isEmpty {
            fields.suggestedKeywords = ["预览", mode == .service ? "服务" : "需求"]
        }
        messages.append(.init(
            id: UUID().uuidString,
            role: "assistant",
            content: "预览模式：已整理到右侧（未请求服务端）",
            toolArgs: [
                "title": fields.title,
                "description": fields.description,
                "category": fields.category,
                "budget": fields.budget,
                "serviceType": fields.serviceType ?? "ONLINE",
            ]
        ))
    }

    private func finishStreamingFlags() {
        for i in messages.indices where messages[i].isStreaming {
            messages[i].isStreaming = false
        }
    }

    private func clearWorkspaceContent() {
        streamTask?.cancel()
        streamTask = nil
        messages = []
        fields = PublishWorkspaceFields()
        lockedFields = []
        lockedKeywords = []
        expandedMessageIds = []
        missingQueue = PublishMissingQueueState()
        draftInput = ""
        thinkText = ""
        successMessage = nil
        isLoading = false
        canvasMode = false
        confirmPaths = []
    }

    private func restoreOrCreateSession() {
        // 设计预览：每次干净会话，避免 UserDefaults 脏数据污染冒烟/截图
        if frontendPreview {
            clearWorkspaceContent()
            let empty = PublishWorkspaceSessionStore.makeEmpty(kind: workspaceKind)
            activeSessionId = empty.id
            sessions = [empty]
            return
        }
        // 服务卡对齐 Windows：不自动恢复历史
        if mode == .service {
            let empty = PublishWorkspaceSessionStore.makeEmpty(kind: .service)
            activeSessionId = empty.id
            sessions = PublishWorkspaceSessionStore.list(kind: .service)
            return
        }
        sessions = PublishWorkspaceSessionStore.list(kind: .demand)
        if let id = PublishWorkspaceSessionStore.activeId(kind: .demand),
           let snap = PublishWorkspaceSessionStore.get(id, kind: .demand) {
            applySnapshot(snap)
            return
        }
        if let first = sessions.first {
            applySnapshot(first)
            return
        }
        startNewSession()
    }

    private func applySnapshot(_ snap: PublishWorkspaceSessionSnapshot) {
        activeSessionId = snap.id
        messages = snap.messages.map { $0.toMessage() }
        fields = snap.fields.toFields()
        lockedFields = Set(snap.fieldOverrides)
        lockedKeywords = Set(snap.lockedKeywords)
        missingQueue = snap.missingQueue
        draftInput = snap.input
        speedMode = snap.speedMode
        fields.confidence = snap.confidence
        fields.readyToPublish = snap.readyToPublish
        fields.missingInfo = snap.missingInfo.isEmpty ? fields.missingInfo : snap.missingInfo
        PublishWorkspaceSessionStore.setActiveId(snap.id, kind: workspaceKind)
        sessions = PublishWorkspaceSessionStore.list(kind: workspaceKind)
    }

    private func startNewSession() {
        persistActiveSession()
        clearWorkspaceContent()
        let empty = PublishWorkspaceSessionStore.makeEmpty(kind: workspaceKind)
        activeSessionId = empty.id
        PublishWorkspaceSessionStore.upsert(empty, kind: workspaceKind)
        sessions = PublishWorkspaceSessionStore.list(kind: workspaceKind)
    }

    private func loadSession(_ id: String) {
        guard id != activeSessionId else { return }
        persistActiveSession()
        streamTask?.cancel()
        if let snap = PublishWorkspaceSessionStore.get(id, kind: workspaceKind) {
            applySnapshot(snap)
        }
    }

    private func deleteSession(_ id: String) {
        let next = PublishWorkspaceSessionStore.delete(id: id, kind: workspaceKind)
        sessions = PublishWorkspaceSessionStore.list(kind: workspaceKind)
        if id == activeSessionId {
            if let next, let snap = PublishWorkspaceSessionStore.get(next, kind: workspaceKind) {
                applySnapshot(snap)
            } else {
                startNewSession()
            }
        }
    }

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { persistActiveSession() }
        }
    }

    private func persistActiveSession() {
        guard !frontendPreview else { return }
        guard let id = activeSessionId else { return }
        guard mode == .demand || !messages.isEmpty || fields.hasCoreContent else {
            // 服务卡：空会话不强制落盘刷列表
            let snap = PublishWorkspaceSessionSnapshot(
                id: id,
                title: PublishWorkspaceSessionStore.deriveTitle(fields: fields, messages: messages),
                updatedAt: Date().timeIntervalSince1970,
                messages: messages.map(PublishWorkspaceChatMessageDTO.init),
                input: draftInput,
                fields: PublishWorkspaceFieldsDTO(fields),
                fieldOverrides: Array(lockedFields),
                lockedKeywords: Array(lockedKeywords),
                missingInfo: fields.missingInfo,
                missingQueue: missingQueue,
                confidence: fields.confidence,
                readyToPublish: isReady,
                speedMode: speedMode
            )
            if messages.isEmpty && !fields.hasCoreContent { return }
            PublishWorkspaceSessionStore.upsert(snap, kind: workspaceKind)
            sessions = PublishWorkspaceSessionStore.list(kind: workspaceKind)
            return
        }
        let snap = PublishWorkspaceSessionSnapshot(
            id: id,
            title: PublishWorkspaceSessionStore.deriveTitle(fields: fields, messages: messages),
            updatedAt: Date().timeIntervalSince1970,
            messages: messages.map(PublishWorkspaceChatMessageDTO.init),
            input: draftInput,
            fields: PublishWorkspaceFieldsDTO(fields),
            fieldOverrides: Array(lockedFields),
            lockedKeywords: Array(lockedKeywords),
            missingInfo: fields.missingInfo,
            missingQueue: missingQueue,
            confidence: fields.confidence,
            readyToPublish: isReady,
            speedMode: speedMode
        )
        PublishWorkspaceSessionStore.upsert(snap, kind: workspaceKind)
        sessions = PublishWorkspaceSessionStore.list(kind: workspaceKind)
    }

    private func consumeHandoff() {
        guard let handoff = session.consumePublishHandoff() else { return }
        let expected: PublishDraftHandoff.Kind = mode == .demand ? .demand : .service
        guard handoff.kind == expected else { return }
        fields.applyHandoff(handoff)
        if !handoff.description.isEmpty || !handoff.expectedOutcome.isEmpty {
            let seed = handoff.description.isEmpty ? handoff.expectedOutcome : handoff.description
            messages.append(.init(id: UUID().uuidString, role: "user", content: seed))
            messages.append(.init(
                id: UUID().uuidString,
                role: "assistant",
                content: "已从九木助手带入草稿，请在右侧核对后发布。"
            ))
        }
        persistActiveSession()
    }

    private func loadRegions() async {
        guard !frontendPreview else { return }
        let meta = await session.demandPublishRepository.loadMetadata()
        regions = meta.regions
    }

    private func beginPublishFlow() {
        let issues = mode == .demand
            ? fields.validateForDemandPublish()
            : fields.validateForServicePublish()
        if !issues.isEmpty {
            errorMessage = issues.map(\.message).joined(separator: "；")
            return
        }
        // Windows：服务卡直接创建草稿，不进 paths 页
        if mode == .service {
            confirmPaths = fields.derivedPaths
            Task { await publishService() }
            return
        }
        confirmPaths = fields.derivedPaths
        if confirmPaths.isEmpty, !fields.category.isEmpty {
            confirmPaths = ["cat:\(fields.category)"]
        }
        showConfirmPublish = true
    }

    /// Windows `handlePublishFromChat`：先套用 toolArgs，再走发布流。
    private func handlePublishFromChat(_ args: [String: String]) {
        fields.applyAgentArgs(args, locked: lockedFields)
        if isReady {
            beginPublishFlow()
        } else {
            errorMessage = "信息尚不完整，请先在右侧工作区补全必填项"
        }
    }

    @MainActor
    private func commitPublishFromConfirm() async {
        isPublishing = true
        defer { isPublishing = false }
        if mode == .service {
            await publishService()
        } else {
            await publishDemand()
        }
        if errorMessage == nil {
            showConfirmPublish = false
        }
    }

    @MainActor
    private func publishService() async {
        if frontendPreview {
            successMessage = "预览模式：已模拟保存服务卡草稿"
            startNewSession()
            return
        }
        var draft = ServiceCardDraft()
        draft.title = fields.title
        draft.summary = String(fields.description.prefix(240))
        draft.description = fields.description
        draft.category = fields.category
        draft.serviceType = fields.serviceType ?? "ONLINE"
        draft.deliveryMode = fields.schedule.isEmpty ? "REMOTE" : fields.schedule
        let prices = fields.budget.matches(of: #/\d+(?:\.\d+)?/#).compactMap { Decimal(string: String($0.output)) }
        if let first = prices.first {
            draft.priceMinText = "\(first)"
            draft.priceMaxText = "\(prices.count > 1 ? prices[1] : first)"
        }
        draft.claims = Array(Set(confirmPaths + fields.scopeLabels + fields.suggestedKeywords))
        do {
            let command = try draft.publishCommand()
            let body = ServiceCardInputBody(
                title: command.title,
                summary: command.summary,
                description: command.description,
                category: command.category,
                serviceType: command.serviceType,
                tags: command.tags.isEmpty ? nil : command.tags,
                priceMin: command.priceMin.map { NSDecimalNumber(decimal: $0).doubleValue },
                priceMax: command.priceMax.map { NSDecimalNumber(decimal: $0).doubleValue },
                deliveryMode: command.deliveryMode,
                availability: "AVAILABLE"
            )
            _ = try await session.serviceCardService.create(body)
            successMessage = "服务卡草稿已保存"
            startNewSession()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @MainActor
    private func publishDemand() async {
        if frontendPreview {
            successMessage = "预览模式：已模拟发布需求"
            startNewSession()
            return
        }
        var draft = DemandDraft()
        draft.title = fields.title
        draft.expectedOutcome = fields.resolvedExpectedOutcome
        draft.allowsNearbyDiscovery = fields.serviceType == "OFFLINE"
        draft.selectedRegionID = fields.regionId
        var tags = Set(confirmPaths)
        if !fields.category.isEmpty { tags.insert(fields.category) }
        for label in fields.scopeLabels { tags.insert(label) }
        draft.selectedTags = tags
        draft.applicantLimit = fields.maxApplicants
        if let minutes = fields.timeLimitMinutes {
            draft.timeLimitMinutes = minutes
        }
        let prices = fields.budget.matches(of: #/\d+(?:\.\d+)?/#).compactMap { Decimal(string: String($0.output)) }
        if let first = prices.first {
            draft.minimumPriceText = "\(first)"
            if prices.count > 1 {
                draft.expectedPriceText = "\(prices[1])"
            }
        }
        do {
            let command = try draft.publishCommand()
            try await session.demandPublishRepository.publish(command, files: [], idempotencyKey: UUID().uuidString)
            successMessage = "需求已发布"
            startNewSession()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct FlowTags: View {
    let tags: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.fill.opacity(0.4), in: Capsule())
            }
        }
    }
}
