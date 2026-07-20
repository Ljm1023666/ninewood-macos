import PhotosUI
import SwiftUI

struct MessagesView: View {
    enum InboxMode: String, CaseIterable, Identifiable {
        case direct = "私聊"
        case merge = "群聊"
        var id: String { rawValue }
    }

    @Environment(AppSession.self) private var session
    @State private var model: MessagesFeatureModel
    @State private var inboxMode: InboxMode = .direct
    @State private var showNotifications = false
    @State private var merges: [MergeChatDTO] = []
    @State private var selectedMerge: MergeChatDTO?
    @State private var mergesError: String?
    @State private var isLoadingMerges = false
    @State private var showCreateMerge = false
    private let previewBubbles: [ChatBubbleKind]?
    private let previewThreads: [ChatThread]?
    private let previewMerges: [MergeChatDTO]?
    private let previewMergeBubbles: [ChatBubbleKind]?

    init(
        repository: MessageRepository,
        previewThreads: [ChatThread]? = nil,
        previewBubbles: [ChatBubbleKind]? = nil,
        previewMerges: [MergeChatDTO]? = nil,
        previewMergeBubbles: [ChatBubbleKind]? = nil,
        initialMode: InboxMode = .direct
    ) {
        _model = State(initialValue: MessagesFeatureModel(
            repository: repository,
            previewThreads: previewThreads
        ))
        self.previewBubbles = previewBubbles
        self.previewThreads = previewThreads
        self.previewMerges = previewMerges
        self.previewMergeBubbles = previewMergeBubbles
        _inboxMode = State(initialValue: initialMode)
        _merges = State(initialValue: previewMerges ?? [])
        _selectedMerge = State(initialValue: previewMerges?.first)
    }

    private var useStaticFixtures: Bool {
        previewThreads != nil || previewBubbles != nil || previewMerges != nil || previewMergeBubbles != nil
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if inboxMode == .direct {
                MessagesReferencePreview(
                    inboxMode: $inboxMode,
                    listModel: model,
                    useStaticFixtures: useStaticFixtures,
                    previewBubbles: previewBubbles,
                    onThreadOpened: { clearUnread(for: $0) }
                )
            } else {
                GroupMessagesReferencePreview(
                    inboxMode: $inboxMode,
                    merges: $merges,
                    selectedMerge: $selectedMerge,
                    useStaticFixtures: useStaticFixtures,
                    previewMergeBubbles: previewMergeBubbles,
                    mergesError: mergesError,
                    isLoadingMerges: isLoadingMerges,
                    onRefreshMerges: { await loadMerges() },
                    onShowNotifications: { showNotifications = true },
                    onShowCreateMerge: { showCreateMerge = true }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.surface)
        .navigationTitle("消息")
        .animation(nil, value: inboxMode)
        .sheet(isPresented: $showNotifications) {
            NotificationsView()
                .environment(session)
                .frame(minWidth: 480, minHeight: 520)
        }
        .sheet(isPresented: $showCreateMerge) {
            CreateMergeChatSheet { created in
                merges.insert(created, at: 0)
                selectedMerge = created
                inboxMode = .merge
            }
            .environment(session)
            .frame(minWidth: 520, minHeight: 560)
        }
        .onAppear {
            guard !useStaticFixtures else { return }
            Task { await openPendingDirectPeerIfNeeded() }
        }
        .task {
            guard !useStaticFixtures else { return }
            await refreshInbox(forceFull: true)
            await openPendingDirectPeerIfNeeded()
        }
        .task(id: inboxMode) {
            guard !useStaticFixtures else {
                if inboxMode == .merge, previewMerges == nil { await loadMerges() }
                return
            }
            // 切 Tab 时才拉对应列表；避免与上面 .task 叠加重载
            if inboxMode == .merge {
                await loadMerges()
            }
        }
        .onChange(of: session.chatRealtime.inboxEpoch) { _, epoch in
            guard !useStaticFixtures else { return }
            // 防抖全量校正：短时内多次 Socket 只落一次；日常列表靠 lastIncoming 补丁
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                guard session.chatRealtime.inboxEpoch == epoch else { return }
                await refreshInbox(forceFull: true)
            }
        }
        .onChange(of: session.chatRealtime.lastIncoming) { _, incoming in
            guard !useStaticFixtures, let incoming, inboxMode == .direct else { return }
            if let userID = session.currentUserId {
                model.applyIncomingPreview(incoming, currentUserID: userID)
            }
        }
        .onChange(of: session.navigation.request) { _, request in
            guard request != nil, !useStaticFixtures else { return }
            if session.navigation.currentPath == "/messages/group" {
                inboxMode = .merge
            }
            Task { await openPendingDirectPeerIfNeeded() }
        }
        .onChange(of: model.selected?.id) { _, newID in
            if let newID { clearUnread(for: newID) }
        }
    }

    private func refreshInbox(forceFull: Bool) async {
        if inboxMode == .direct {
            guard forceFull else { return }
            await model.load()
        } else {
            await loadMerges()
        }
    }

    /// 找人/关注「发消息」：切到私聊并聚焦该用户（可并发调用，pending 只消费一次）。
    private func openPendingDirectPeerIfNeeded() async {
        guard session.navigation.hasPendingDirectPeer else { return }
        inboxMode = .direct
        guard let peerID = session.navigation.consumePendingDirectPeerID() else { return }
        model.beginFocus(peerID: peerID)
        await model.load()
        await model.focusPeer(peerID) {
            try await session.userService.get(id: peerID)
        }
    }

    private func clearUnread(for threadId: String) {
        let unread = model.clearUnread(threadID: threadId)
        guard unread > 0 else { return }
        session.applyLocalRead(count: unread)
    }

    private func loadMerges() async {
        if let previewMerges {
            merges = previewMerges
            selectedMerge = selectedMerge ?? previewMerges.first
            return
        }
        isLoadingMerges = true
        mergesError = nil
        defer { isLoadingMerges = false }
        do {
            let rows = try await session.messageRepository.merges()
            merges = rows
            if let selectedID = selectedMerge?.id {
                // 保持用户选中；勿在刷新时跳到列表第一项
                selectedMerge = rows.first(where: { $0.id == selectedID }) ?? selectedMerge
            } else {
                selectedMerge = rows.first
            }
        } catch {
            merges = []
            selectedMerge = nil
            mergesError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct MessagesInboxModePills: View {
    @Binding var inboxMode: MessagesView.InboxMode

    var body: some View {
        HStack(spacing: 0) {
            modePill("私聊", mode: .direct)
            modePill("群聊", mode: .merge)
        }
        .padding(3)
        .background(AppTheme.surfaceLow, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func modePill(_ title: String, mode: MessagesView.InboxMode) -> some View {
        Button {
            inboxMode = mode
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(inboxMode == mode ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    inboxMode == mode ? AppTheme.primary : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}

private enum MessagesInboxLayoutMetrics {
    static let listWidth: CGFloat = 268
    static let inspectorWidth: CGFloat = 236
    /// 群聊「通知 / 新建群聊」行高度；私聊留同等占位，避免 Tab 切换时列表头错位。
    static let listToolbarHeight: CGFloat = 28
}

/// 群聊/私聊输入区：实心 #2FBBE0 发送按钮（对齐 ui-renderings/11）
private struct MessagesSolidSendButton: View {
    let title: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 64)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(
                    disabled ? AppTheme.primary.opacity(0.45) : AppTheme.primary,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

@ViewBuilder
private func messagesSolidSendButton(
    title: String,
    disabled: Bool = false,
    action: @escaping () -> Void
) -> some View {
    MessagesSolidSendButton(title: title, disabled: disabled, action: action)
}

private struct MessagesThreeColumnShell<List: View, Chat: View, Inspector: View>: View {
    @ViewBuilder var list: () -> List
    @ViewBuilder var chat: () -> Chat
    @ViewBuilder var inspector: () -> Inspector

    var body: some View {
        HStack(spacing: 0) {
            list()
                .frame(width: MessagesInboxLayoutMetrics.listWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(AppTheme.surface)
            Divider()
            chat()
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            inspector()
                .frame(width: MessagesInboxLayoutMetrics.inspectorWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(AppTheme.surface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.surface)
    }
}

private struct MessagesListSearchBar: View {
    let placeholder: String
    @Binding var text: String
    var showsFilterIcon = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
            Spacer(minLength: 0)
            if showsFilterIcon {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

private struct MessagesListHeader<Toolbar: View>: View {
    @Binding var inboxMode: MessagesView.InboxMode
    @Binding var searchText: String
    let searchPlaceholder: String
    var showsFilterIcon = false
    @ViewBuilder var toolbar: () -> Toolbar

    var body: some View {
        VStack(spacing: 0) {
            toolbar()
                .frame(height: MessagesInboxLayoutMetrics.listToolbarHeight)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 10)

            MessagesInboxModePills(inboxMode: $inboxMode)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            MessagesListSearchBar(
                placeholder: searchPlaceholder,
                text: $searchText,
                showsFilterIcon: showsFilterIcon
            )
        }
    }
}

private struct MessagesReferencePreview: View {
    @Environment(AppSession.self) private var session
    @Binding var inboxMode: MessagesView.InboxMode
    @Bindable var listModel: MessagesFeatureModel
    var useStaticFixtures: Bool
    var previewBubbles: [ChatBubbleKind]?
    var onThreadOpened: ((String) -> Void)?

    @State private var fixtureSelected = 0
    @State private var draft = ""
    @State private var chatModel: ChatDetailFeatureModel?
    @State private var isExtendingCommunication = false
    @State private var showCardPicker = false
    @State private var dmPhotoItem: PhotosPickerItem?
    @State private var openedDemandID: String?
    @State private var openedServiceCardID: String?
    @State private var cardOpenError: String?
    @State private var showSafetyGuide = false

    private let rows: [(String, String, String, Int, String?, Bool)] = [
        ("林夏", "好的，我看看这个需求卡，稍后给你反馈。", "14:32", 2, "AvatarLinXia", true),
        ("陈述", "感谢！我会尽快处理。", "13:07", 1, "AvatarChenShu", false),
        ("产品研究小队", "张默：明天 10 点例会", "12:45", 5, nil, false),
        ("张默", "关于用户访谈的安排", "11:20", 0, "AvatarZhangMo", false),
        ("九木小助手", "你的认证已通过审核", "昨天", 0, nil, true),
        ("许言", "稍后把资料发你", "昨天", 0, "AvatarXuYan", false),
        ("设计共创群", "Lily：好的，收到", "周二", 0, nil, false),
        ("方舟", "已发送需求卡", "周一", 0, "AvatarFangZhou", false),
        ("系统通知", "平台规则更新通知", "周一", 0, nil, true)
    ]

    var body: some View {
        MessagesThreeColumnShell {
            conversationList
        } chat: {
            if useStaticFixtures {
                chat
            } else {
                liveChat
            }
        } inspector: {
            inspector
        }
        .onChange(of: listModel.selected?.id) { _, newID in
            syncChatModel(peerID: newID)
        }
        .task(id: listModel.selected?.id) {
            guard !useStaticFixtures else { return }
            let peerID = listModel.selected?.id
            syncChatModel(peerID: peerID)
            if let peerID {
                onThreadOpened?(peerID)
                await chatModel?.load()
            }
        }
        .onChange(of: session.chatRealtime.lastIncoming) { _, incoming in
            guard !useStaticFixtures, let incoming else { return }
            if incoming.hasCardAttachment {
                Task { await chatModel?.load() }
            } else {
                chatModel?.appendRealtime(incoming)
            }
        }
        .sheet(isPresented: $showCardPicker) {
            MessageCardPicker { type, id in
                showCardPicker = false
                Task { await chatModel?.sendCard(type: type, cardID: id) }
            }
            .environment(session)
            .frame(minWidth: 520, minHeight: 460)
        }
        .sheet(item: Binding(
            get: { openedDemandID.map(IdentifiableString.init) },
            set: { openedDemandID = $0?.value }
        )) { item in
            NavigationStack {
                DemandDetailLoaderView(demandID: item.value)
            }
            .environment(session)
            .frame(minWidth: 720, minHeight: 640)
        }
        .sheet(item: Binding(
            get: { openedServiceCardID.map(IdentifiableString.init) },
            set: { openedServiceCardID = $0?.value }
        )) { item in
            NavigationStack {
                ServiceCardLoaderView(cardID: item.value)
            }
            .environment(session)
            .frame(minWidth: 560, minHeight: 480)
        }
        .alert("无法打开卡片", isPresented: Binding(
            get: { cardOpenError != nil },
            set: { if !$0 { cardOpenError = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(cardOpenError ?? "")
        }
        .onChange(of: dmPhotoItem) { _, item in
            guard let item else { return }
            Task {
                await sendDirectPhoto(item)
                dmPhotoItem = nil
            }
        }
    }

    private func sendDirectPhoto(_ item: PhotosPickerItem) async {
        guard let chatModel else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                chatModel.errorMessage = "无法读取所选图片"
                return
            }
            await chatModel.sendImage(
                data: data,
                fileName: "dm_\(Int(Date().timeIntervalSince1970)).jpg",
                mimeType: "image/jpeg"
            )
        } catch {
            chatModel.errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func openLiveCard(_ attachment: ChatCardAttachment) {
        guard let cardID = attachment.cardID, !cardID.isEmpty else {
            cardOpenError = "卡片缺少业务对象 ID"
            return
        }
        switch attachment.kind {
        case .demand:
            openedDemandID = cardID
        case .serviceCard:
            openedServiceCardID = cardID
        case .unknown:
            cardOpenError = "暂不支持打开此类卡片"
        }
    }

    private func syncChatModel(peerID: String?) {
        guard !useStaticFixtures,
              let peerID,
              let thread = listModel.selected,
              thread.peer.id == peerID || thread.id == peerID,
              let userID = session.currentUserId else {
            if peerID == nil { chatModel = nil }
            return
        }
        if let existing = chatModel, existing.thread.peer.id == thread.peer.id {
            existing.applyThreadMetadata(thread)
            return
        }
        chatModel = ChatDetailFeatureModel(
            thread: thread,
            currentUserID: userID,
            repository: session.messageRepository,
            previewBubbles: previewBubbles
        )
    }

    private var liveChat: some View {
        Group {
            if let chatModel {
                liveChatColumn(chatModel)
            } else {
                VStack {
                    Spacer()
                    Text("选择左侧会话开始聊天")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.surface)
            }
        }
    }

    @ViewBuilder
    private func liveChatColumn(_ chatModel: ChatDetailFeatureModel) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                NWAvatarView(
                    url: chatModel.thread.peer.avatarMediaURL,
                    name: chatModel.thread.peer.name,
                    size: 38
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(chatModel.thread.peer.name).font(.headline)
                    if session.chatRealtime.isConnected {
                        HStack(spacing: 4) {
                            Circle().fill(AppTheme.openStatus).frame(width: 7, height: 7)
                            Text("在线").font(.caption).foregroundStyle(AppTheme.openStatus)
                        }
                    }
                }
                Spacer(minLength: 8)
                if let communication = chatModel.thread.communication {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        HStack(spacing: 4) {
                            Image(systemName: "stopwatch")
                            Text(communication.remainingText(at: context.date))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    if communication.canExtend {
                        Button(isExtendingCommunication ? "延长中…" : "延长 5 分钟") {
                            Task { await extendCommunication(chatModel) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isExtendingCommunication)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 64)
            .background(AppTheme.surface)
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if chatModel.isLoading && chatModel.bubbles.isEmpty {
                            ProgressView().padding(.top, 40)
                        }
                        ForEach(Array(chatModel.bubbles.enumerated()), id: \.offset) { index, bubble in
                            liveBubble(bubble, peer: chatModel.thread.peer)
                                .id(index)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: chatModel.bubbles.count) { _, _ in
                    if let last = chatModel.bubbles.indices.last {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
            .background(AppTheme.surface)

            Divider()
            liveComposer(chatModel)
        }
    }

    @ViewBuilder
    private func liveBubble(_ bubble: ChatBubbleKind, peer: AppUser) -> some View {
        switch bubble {
        case .system(let text):
            Text(text).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        case .time(let text):
            timeChip(text)
        case .text(let text, let isMine, _):
            if isMediaMessagePath(text) {
                liveMediaBubble(path: text, isMine: isMine, peer: peer)
            } else if isMine {
                outgoing(text, "")
            } else {
                incoming(text, asset: nil, name: peer.name, avatarURL: peer.avatarMediaURL)
            }
        case .card(let attachment, _):
            HStack {
                if attachment.isMine { Spacer(minLength: 48) }
                Button {
                    openLiveCard(attachment)
                } label: {
                    ChatCardAttachmentChip(attachment: attachment)
                }
                .buttonStyle(.plain)
                if !attachment.isMine { Spacer(minLength: 48) }
            }
        }
    }

    private func isMediaMessagePath(_ text: String) -> Bool {
        text.hasPrefix("/uploads/") || text.contains("/uploads/")
    }

    @ViewBuilder
    private func liveMediaBubble(path: String, isMine: Bool, peer: AppUser) -> some View {
        HStack {
            if isMine { Spacer(minLength: 48) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
                if !isMine {
                    Text(peer.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                NWRemoteImage(url: APIConfig.mediaURL(path), cornerRadius: 10)
                    .frame(width: 200, height: 140)
                    .clipped()
            }
            if !isMine { Spacer(minLength: 48) }
        }
    }

    private func liveComposer(_ model: ChatDetailFeatureModel) -> some View {
        @Bindable var chatModel = model
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    showCardPicker = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(width: 28, height: 28)
                        .background(AppTheme.surfaceLow, in: Circle())
                }
                .buttonStyle(.plain)
                .help(chatModel.canAttachMedia ? "发送我的需求卡或服务卡" : "当前不可发送附件")
                .disabled(!chatModel.canAttachMedia)

                PhotosPicker(selection: $dmPhotoItem, matching: .images) {
                    Image(systemName: "photo")
                        .font(.body.weight(.semibold))
                        .frame(width: 28, height: 28)
                        .background(AppTheme.surfaceLow, in: Circle())
                }
                .buttonStyle(.plain)
                .help(chatModel.canAttachMedia ? "发送图片" : "当前不可发送附件")
                .disabled(!chatModel.canAttachMedia)

                Spacer()
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("输入消息（Enter 发送，⇧+Enter 换行）", text: $chatModel.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .frame(minHeight: 56, maxHeight: 88)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                    }
                    .onSubmit { Task { await chatModel.send() } }
                Button("发送") { Task { await chatModel.send() } }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primary)
                    .frame(width: 64)
                    .disabled(!chatModel.canSend)
            }
        }
        .padding(12)
        .background(AppTheme.surface)
    }

    private func extendCommunication(_ chatModel: ChatDetailFeatureModel) async {
        guard let communication = chatModel.thread.communication else { return }
        isExtendingCommunication = true
        defer { isExtendingCommunication = false }
        do {
            let updated = try await session.demandRepository.extendCommunication(
                demandID: communication.demandID,
                applicantID: communication.applicantID,
                minutes: 5
            )
            chatModel.updateCommunication(
                deadline: APIDate.parse(updated.commDeadline),
                addedMinutes: 5
            )
        } catch {
            chatModel.errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private var conversationList: some View {
        VStack(spacing: 0) {
            MessagesListHeader(
                inboxMode: $inboxMode,
                searchText: $listModel.searchText,
                searchPlaceholder: "搜索会话 / 用户"
            ) {
                Color.clear
            }

            ScrollView {
                LazyVStack(spacing: 2) {
                    if useStaticFixtures {
                        ForEach(rows.indices, id: \.self) { index in
                            Button { fixtureSelected = index } label: {
                                conversationRow(index)
                            }
                            .buttonStyle(.plain)
                        }
                    } else if listModel.isLoading && listModel.threads.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                    } else if let loadError = listModel.errorMessage, listModel.threads.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(loadError).foregroundStyle(.secondary)
                            Button("重新加载") { Task { await listModel.load() } }
                        }
                        .padding(16)
                    } else if listModel.filteredThreads.isEmpty {
                        Text("暂无消息")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                    } else {
                        ForEach(listModel.filteredThreads) { thread in
                            Button { listModel.selectThread(thread) } label: {
                                liveConversationRow(thread)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
    }

    private func liveConversationRow(_ thread: ChatThread) -> some View {
        let isSelected = listModel.selected?.id == thread.id
        return HStack(spacing: 10) {
            NWAvatarView(
                url: thread.peer.avatarMediaURL,
                name: thread.peer.name,
                size: 42
            )
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(thread.peer.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(thread.timeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text(thread.preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if thread.unreadCount > 0 {
                        Text("\(thread.unreadCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .padding(.horizontal, thread.unreadCount > 9 ? 4 : 0)
                            .background(AppTheme.error, in: Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 72)
        .background(
            isSelected ? AppTheme.softPrimary : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    private func conversationRow(_ index: Int) -> some View {
        let row = rows[index]
        return HStack(spacing: 10) {
            referenceAvatar(asset: row.4, name: row.0, size: 42)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(row.0)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if row.5 {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.primary)
                    }
                    Spacer(minLength: 4)
                    Text(row.2)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text(row.1)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if row.3 > 0 {
                        Text("\(row.3)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .padding(.horizontal, row.3 > 9 ? 4 : 0)
                            .background(AppTheme.error, in: Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 72)
        .background(fixtureSelected == index ? AppTheme.softPrimary : Color.clear)
        .overlay(alignment: .leading) {
            if fixtureSelected == index {
                Rectangle()
                    .fill(AppTheme.primary)
                    .frame(width: 3)
            }
        }
    }

    private var chat: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                referenceAvatar(asset: "AvatarLinXia", name: "林夏", size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text("林夏").font(.headline)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.primary)
                    }
                    HStack(spacing: 4) {
                        Circle()
                            .fill(AppTheme.openStatus)
                            .frame(width: 7, height: 7)
                        Text("在线")
                            .font(.caption)
                            .foregroundStyle(AppTheme.openStatus)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Image(systemName: "stopwatch")
                    Text("沟通资格剩余 03:42")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Button("延长 5 分钟") {}
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .disabled(true)
                    .help("设计预览不可延长；线上会话会显示真实剩余时间")
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 64)
            .background(AppTheme.surface)
            Divider()

            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(AppTheme.openStatus)
                Text("对方已通过真实身份认证，可放心沟通")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("查看")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primary)
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(AppTheme.openStatus.opacity(0.10))
            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    timeChip("14:12")
                    incoming("你好，我看到你在做消费电子方向的产品研究，\n想咨询一下有没有档期可以接一个小需求？", asset: "AvatarLinXia")
                    outgoing("你好，感谢关注！可以的，\n请先发一下需求详情和预期时间哈。", "14:13")
                    incoming("好的，我整理了一下需求卡，麻烦帮忙看看～", asset: "AvatarLinXia")
                    outgoing("好的，我看看这个需求卡，稍后给你反馈。", "14:16")
                    timeChip("14:32")
                    demandCard
                }
                .padding(16)
            }
            .background(AppTheme.surface)

            Divider()
            composer
        }
    }

    private func timeChip(_ value: String) -> some View {
        Text(value)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
    }

    private func incoming(_ text: String, asset: String? = nil, name: String = "林夏", avatarURL: URL? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if let avatarURL {
                NWAvatarView(url: avatarURL, name: name, size: 34)
            } else {
                referenceAvatar(asset: asset, name: name, size: 34)
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.onSurface)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppTheme.bubbleIncoming, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Spacer(minLength: 48)
        }
    }

    private func outgoing(_ text: String, _ time: String) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            Spacer(minLength: 64)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                Text(time)
                    .font(.caption2)
            }
            .foregroundStyle(AppTheme.primary)
        }
    }

    private var demandCard: some View {
        HStack(alignment: .top, spacing: 8) {
            referenceAvatar(asset: "AvatarLinXia", name: "林夏", size: 34)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(AppTheme.openStatus, in: Circle())
                    Text("需求卡：智能耳机用户研究")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    NWStatusChip(text: "待确认", tint: AppTheme.openStatus)
                }
                Divider()
                keyValue("需求方", "林夏（已认证）")
                keyValue("预算", "600 点")
                keyValue("交付时间", "2025-05-31 前")
                Divider()
                HStack {
                    Text("查看详情")
                        .foregroundStyle(AppTheme.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(AppTheme.primary)
                }
                .font(.subheadline.weight(.medium))
            }
            .padding(12)
            .frame(maxWidth: 320)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
            }
            Spacer(minLength: 0)
        }
    }

    private func keyValue(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.caption)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {} label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(width: 28, height: 28)
                        .background(AppTheme.surfaceLow, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(true)
                .help("设计预览不可发卡")
                Button {} label: {
                    Label("需求卡", systemImage: "rectangle.stack")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Color.white,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(true)
                .help("设计预览不可发卡")
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("输入消息（Enter 发送，⇧+Enter 换行）", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .frame(minHeight: 56, maxHeight: 88)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                    }
                Button("发送") {}
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .frame(width: 64, height: 36)
                    .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .disabled(true)
                    .help("设计预览不可发送；线上会话可真实发消息")
            }
        }
        .padding(12)
        .background(AppTheme.surface)
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if useStaticFixtures {
                    fixtureInspectorContent
                } else {
                    liveInspectorContent
                }

                Text("安全提示").font(.headline)
                VStack(alignment: .leading, spacing: 10) {
                    safety("请在九木内沟通与交易", "平台提供沟通记录保护", true)
                    safety("需求未确认前不要提供联系方式", "保护个人隐私与账号安全", true)
                    safety("警惕纷争与虚假需求", "发现问题可举报处理", false)
                }

                Divider()
                Button {
                    showSafetyGuide = true
                } label: {
                    HStack {
                        Text("查看《安全沟通指南》")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(AppTheme.primary)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .sheet(isPresented: $showSafetyGuide) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("安全沟通指南")
                            .font(.title2.bold())
                        Text("请在九木平台内完成沟通与交易。平台托管与沟通记录用于保护双方权益。")
                            .foregroundStyle(.secondary)
                        Text("需求未确认前，不要交换个人联系方式或进行站外转账。")
                            .foregroundStyle(.secondary)
                        Text("警惕虚假需求、诱导私下付款或索要敏感信息；发现问题请使用举报入口。")
                            .foregroundStyle(.secondary)
                        Text("更多说明见侧栏「帮助」→「沟通与社区」。")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { showSafetyGuide = false }
                    }
                }
            }
            .frame(minWidth: 420, minHeight: 320)
        }
    }

    @ViewBuilder
    private var liveInspectorContent: some View {
        let thread = chatModel?.thread ?? listModel.selected
        if let thread {
            HStack(spacing: 12) {
                NWAvatarView(
                    url: thread.peer.avatarMediaURL,
                    name: thread.peer.name,
                    size: 48
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(thread.peer.name)
                        .font(.headline)
                    if let remaining = thread.remainingCommText ?? thread.communication.map({ $0.remainingText() }) {
                        Text(remaining)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if let title = thread.relatedDemandTitle, !title.isEmpty {
                Text("关联需求").font(.headline)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(AppTheme.openStatus, in: Circle())
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 4)
                    }
                }
                .padding(12)
                .ninewoodCard()
            }

            if let communication = thread.communication {
                Text("沟通信息").font(.headline)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundStyle(AppTheme.primary)
                        Text("沟通资格剩余")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(communication.remainingText(at: context.date))
                            .font(.title.bold())
                            .foregroundStyle(AppTheme.primary)
                    }
                    if communication.canExtend {
                        Button(isExtendingCommunication ? "延长中…" : "延长 5 分钟") {
                            if let chatModel {
                                Task { await extendCommunication(chatModel) }
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .disabled(isExtendingCommunication || chatModel == nil)
                    }
                }
                .padding(12)
                .ninewoodCard()
            }
        } else {
            Text("选择会话查看详情")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var fixtureInspectorContent: some View {
        Text("关联需求").font(.headline)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.openStatus, in: Circle())
                Text("智能耳机用户研究")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                NWStatusChip(text: "待确认", tint: AppTheme.openStatus)
            }
            keyValue("预算", "600 点")
            keyValue("交付时间", "2025-05-31 前")
            Divider()
            HStack {
                Text("查看详情").foregroundStyle(AppTheme.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(AppTheme.primary)
            }
            .font(.subheadline.weight(.medium))
        }
        .padding(12)
        .ninewoodCard()

        Text("沟通信息").font(.headline)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(AppTheme.primary)
                Text("沟通资格剩余")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("03:42")
                .font(.title.bold())
                .foregroundStyle(AppTheme.primary)
            Divider()
            keyValue("开始时间", "14:10")
            keyValue("可沟通至", "18:10")
            Button("延长 5 分钟") {}
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryLabel)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .disabled(true)
                .help("设计预览不可延长")
        }
        .padding(12)
        .ninewoodCard()
    }

    private func safety(_ title: String, _ detail: String, _ okay: Bool) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: okay ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(okay ? AppTheme.openStatus : AppTheme.urgent)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption.weight(.medium))
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func referenceAvatar(asset: String?, name: String, size: CGFloat) -> some View {
        if name == "设计共创群" {
            groupCollageAvatar(size: size)
        } else {
            Group {
                if let asset {
                    Image(asset).resizable().scaledToFill()
                } else if name.contains("小队") || name.contains("群") {
                    Image(systemName: "person.3.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.22)
                        .foregroundStyle(.secondary)
                } else if name == "系统通知" {
                    Image(systemName: "bell.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.26)
                        .foregroundStyle(.white)
                        .background(AppTheme.primary)
                } else if name == "九木小助手" {
                    Image("NinewoodLogo")
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.14)
                } else {
                    Image("NinewoodLogo")
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.14)
                }
            }
            .frame(width: size, height: size)
            .background(AppTheme.surfaceLow)
            .clipShape(Circle())
        }
    }

    private func groupCollageAvatar(size: CGFloat) -> some View {
        let cell = (size - 3) / 2
        return VStack(spacing: 1) {
            HStack(spacing: 1) {
                collageCell("AvatarLinXia", size: cell)
                collageCell("AvatarZhangMo", size: cell)
            }
            HStack(spacing: 1) {
                collageCell("AvatarXuYan", size: cell)
                collageCell("AvatarFangZhou", size: cell)
            }
        }
        .frame(width: size, height: size)
        .background(AppTheme.surfaceLow)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    private func collageCell(_ asset: String, size: CGFloat) -> some View {
        Image(asset)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipped()
    }
}

private struct GroupMessagesReferencePreview: View {
    @Environment(AppSession.self) private var session
    @Binding var inboxMode: MessagesView.InboxMode
    @Binding var merges: [MergeChatDTO]
    @Binding var selectedMerge: MergeChatDTO?
    var useStaticFixtures: Bool
    var previewMergeBubbles: [ChatBubbleKind]?
    var mergesError: String?
    var isLoadingMerges: Bool
    var onRefreshMerges: () async -> Void
    var onShowNotifications: () -> Void
    var onShowCreateMerge: () -> Void

    @State private var fixtureSelected = 0
    @State private var draft = ""
    @State private var searchText = ""
    @State private var muteNotifications = false
    @State private var infoTab = 0
    @State private var showChatSearch = false
    @State private var chatSearchText = ""
    @State private var liveBubbles: [ChatBubbleKind] = []
    @State private var isLoadingLive = false
    @State private var isSendingLive = false
    @State private var liveError: String?
    @State private var showAddMembers = false
    @State private var liveSharedFiles: [(String, String, Color)] = []
    @State private var mergePhotoItem: PhotosPickerItem?
    @State private var isSendingMergeFile = false

    private var filteredMerges: [MergeChatDTO] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return merges }
        return merges.filter { $0.displayTitle.localizedCaseInsensitiveContains(query) }
    }

    private let groups: [(String, String, String, Int, [String])] = [
        ("产品研究协作组", "张明：服务框架图已更新", "10:24", 3, ["AvatarLinXia", "AvatarZhangMo", "AvatarXuYan", "AvatarFangZhou"]),
        ("增长实验小组", "李想：本周转化漏斗已同步", "09:56", 2, ["AvatarChenShu", "AvatarLinXia", "AvatarXuYan", "AvatarZhangMo"]),
        ("设计评审会", "方舟：视觉稿 v3 已上传", "08:40", 0, ["AvatarFangZhou", "AvatarZhangMo", "AvatarLinXia", "AvatarChenShu"]),
        ("技术交流圈", "陈述：接口联调完成", "昨天", 1, ["AvatarChenShu", "AvatarXuYan", "AvatarFangZhou", "AvatarLinXia"]),
        ("用户研究互助群", "林夏：招募问卷已发出", "昨天", 0, ["AvatarLinXia", "AvatarChenShu", "AvatarZhangMo", "AvatarFangZhou"]),
        ("品牌共创工作室", "许言：提案提纲见附件", "星期一", 0, ["AvatarXuYan", "AvatarFangZhou", "AvatarLinXia", "AvatarZhangMo"]),
        ("项目管理办公室", "系统：周报已生成", "上周五", 0, ["AvatarZhangMo", "AvatarChenShu", "AvatarXuYan", "AvatarLinXia"])
    ]

    private let members: [(String, String, String?, String)] = [
        ("张明", "产品经理", "群主", "AvatarZhangMo"),
        ("李想", "用户研究", nil, "AvatarLinXia"),
        ("孙悦", "设计师", nil, "AvatarFangZhou"),
        ("陈述", "后端工程师", nil, "AvatarChenShu"),
        ("许言", "前端工程师", nil, "AvatarXuYan"),
        ("林夏", "研究顾问", nil, "AvatarLinXia")
    ]

    private let sharedFiles: [(String, String, Color)] = [
        ("竞品对比分析.xlsx", "09:41 李想 更新", Color(red: 0.18, green: 0.64, blue: 0.38)),
        ("用户访谈提纲.pdf", "昨天 许言 上传", Color(red: 0.86, green: 0.24, blue: 0.24)),
        ("服务框架图.drawio", "10:24 张明 更新", Color(red: 0.95, green: 0.55, blue: 0.18))
    ]

    var body: some View {
        MessagesThreeColumnShell {
            groupList
        } chat: {
            if useStaticFixtures {
                chat
            } else if let merge = selectedMerge {
                liveGroupChat(merge)
            } else {
                VStack {
                    Spacer()
                    Text("选择左侧群聊查看消息")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.surfaceLow.opacity(0.35))
            }
        } inspector: {
            inspector
        }
        .task(id: selectedMerge?.id) {
            guard !useStaticFixtures, let merge = selectedMerge else { return }
            await loadLiveMergeMessages()
            await loadSharedFiles(mergeId: merge.id)
        }
    }

    private func liveGroupChat(_ merge: MergeChatDTO) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                liveMemberCollage(members: merge.members ?? [], size: 48)

                VStack(alignment: .leading, spacing: 6) {
                    Text("\(merge.displayTitle) · \(merge.memberCount)人")
                        .font(.headline)
                    Text("群聊")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Button {
                        withAnimation { showChatSearch.toggle() }
                        if !showChatSearch { chatSearchText = "" }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("搜索本群消息")
                    Button {
                        infoTab = 0
                    } label: {
                        Image(systemName: "list.bullet")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("群信息")
                    Button {
                        infoTab = 1
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("群设置")
                }
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppTheme.surface)
            Divider()

            if showChatSearch {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索本群消息", text: $chatSearchText)
                        .textFieldStyle(.plain)
                    if !chatSearchText.isEmpty {
                        Button("清除") { chatSearchText = "" }
                            .buttonStyle(.plain)
                            .font(.caption)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppTheme.surfaceLow)
                Divider()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if isLoadingLive && liveBubbles.isEmpty {
                            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                        }
                        ForEach(Array(filteredLiveBubbles.enumerated()), id: \.offset) { index, bubble in
                            liveGroupBubble(bubble).id(index)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: liveBubbles.count) { _, _ in
                    if let last = liveBubbles.indices.last {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
            .background(AppTheme.surfaceLow.opacity(0.35))

            Divider()
            liveGroupComposer
        }
        .alert("群聊", isPresented: Binding(
            get: { liveError != nil },
            set: { if !$0 { liveError = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(liveError ?? "")
        }
    }

    @ViewBuilder
    private func liveGroupBubble(_ bubble: ChatBubbleKind) -> some View {
        switch bubble {
        case .system(let text), .time(let text):
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        case .text(let text, let isMine, let sender):
            if isMine {
                HStack {
                    Spacer(minLength: 48)
                    Text(text)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.white)
                }
            } else {
                liveGroupMessage(
                    name: sender?.name ?? "成员",
                    time: "",
                    avatarURL: sender?.avatarURL,
                    text: text
                )
            }
        case .card(let attachment, let sender):
            liveGroupMessage(
                name: attachment.isMine ? "我" : (sender?.name ?? "成员"),
                time: "",
                avatarURL: attachment.isMine ? nil : sender?.avatarURL,
                text: attachment.summary ?? attachment.title
            ) {
                liveAttachmentCard(attachment)
            }
        }
    }

    private func liveGroupMessage<Content: View>(
        name: String,
        time: String,
        avatarURL: URL?,
        text: String,
        @ViewBuilder extra: () -> Content = { EmptyView() }
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            NWAvatarView(url: avatarURL, name: name, size: 36)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if !time.isEmpty {
                        Text(time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.onSurface)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppTheme.bubbleIncoming, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                    }
                extra()
            }
        }
    }

    private func liveAttachmentCard(_ attachment: ChatCardAttachment) -> some View {
        ChatCardAttachmentChip(attachment: attachment)
    }

    private var liveGroupComposer: some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $mergePhotoItem, matching: .images) {
                Image(systemName: "photo")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(isSendingLive || isSendingMergeFile || selectedMerge == nil)
            .help("发送图片")

            TextField("输入消息…", text: $draft)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                }
                .onSubmit { Task { await sendLiveMergeMessage() } }
            messagesSolidSendButton(
                title: isSendingLive || isSendingMergeFile ? "发送中…" : "发送",
                disabled: draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendingLive || isSendingMergeFile
            ) {
                Task { await sendLiveMergeMessage() }
            }
        }
        .padding(12)
        .background(AppTheme.surface)
        .onChange(of: mergePhotoItem) { _, item in
            guard let item else { return }
            Task { await sendLiveMergeFile(item) }
        }
    }

    private func loadLiveMergeMessages() async {
        guard let merge = selectedMerge,
              let userID = session.currentUserId else { return }
        if let previewMergeBubbles, useStaticFixtures {
            liveBubbles = previewMergeBubbles
            return
        }
        isLoadingLive = true
        defer { isLoadingLive = false }
        do {
            liveBubbles = try await session.messageRepository.mergeMessages(
                mergeID: merge.id,
                currentUserID: userID
            )
        } catch {
            liveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func sendLiveMergeMessage() async {
        guard let merge = selectedMerge else { return }
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        isSendingLive = true
        defer { isSendingLive = false }
        do {
            try await session.messageRepository.sendMergeMessage(mergeID: merge.id, content: content)
            draft = ""
            await loadLiveMergeMessages()
        } catch {
            liveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func sendLiveMergeFile(_ item: PhotosPickerItem) async {
        guard let merge = selectedMerge else { return }
        isSendingMergeFile = true
        defer {
            isSendingMergeFile = false
            mergePhotoItem = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else {
            liveError = "无法读取所选图片"
            return
        }
        let file = MultipartFile(
            fieldName: "file",
            fileName: "merge_\(Int(Date().timeIntervalSince1970)).jpg",
            mimeType: "image/jpeg",
            data: data
        )
        do {
            try await session.messageRepository.sendMergeMessage(
                mergeID: merge.id,
                content: "[图片]",
                file: file
            )
            await loadLiveMergeMessages()
            await loadSharedFiles(mergeId: merge.id)
        } catch {
            liveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var groupList: some View {
        VStack(spacing: 0) {
            MessagesListHeader(
                inboxMode: $inboxMode,
                searchText: $searchText,
                searchPlaceholder: "搜索群聊",
                showsFilterIcon: false
            ) {
                HStack(spacing: 8) {
                    Button(action: onShowNotifications) {
                        listActionLabel("通知", systemImage: "bell")
                    }
                    .buttonStyle(.plain)
                    Button(action: onShowCreateMerge) {
                        listActionLabel("新建群聊", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    Button {
                        Task { await onRefreshMerges() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(AppTheme.surface, in: Circle())
                            .overlay { Circle().strokeBorder(AppTheme.outlineVariant, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                }
            }

            ScrollView {
                LazyVStack(spacing: 2) {
                    if useStaticFixtures {
                        ForEach(groups.indices, id: \.self) { index in
                            Button { fixtureSelected = index } label: {
                                groupRow(index)
                            }
                            .buttonStyle(.plain)
                        }
                    } else if isLoadingMerges && merges.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                    } else if let mergesError, merges.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(mergesError).foregroundStyle(.secondary)
                            Button("重新加载") { Task { await onRefreshMerges() } }
                        }
                        .padding(16)
                    } else if merges.isEmpty {
                        Text("暂无群聊")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                    } else if filteredMerges.isEmpty {
                        Text("无匹配群聊")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                    } else {
                        ForEach(filteredMerges) { merge in
                            Button { selectedMerge = merge } label: {
                                liveGroupRow(merge)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
    }

    private func listActionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
            }
    }

    private func liveGroupRow(_ merge: MergeChatDTO) -> some View {
        let isSelected = selectedMerge?.id == merge.id
        return HStack(alignment: .top, spacing: 10) {
            liveMemberCollage(members: merge.members ?? [], size: 44)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(merge.displayTitle)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                }
                Text("\(merge.memberCount) 人")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .nwSelectionChrome(isSelected: isSelected, cornerRadius: 10)
    }

    private func listAction(_ title: String, systemImage: String) -> some View {
        Button {} label: {
            listActionLabel(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }

    private func groupRow(_ index: Int) -> some View {
        let row = groups[index]
        return HStack(alignment: .top, spacing: 10) {
            collageAvatar(assets: row.4, size: 44)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(row.0)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(row.2)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text(row.1)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if row.3 > 0 {
                        Text("\(row.3)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .padding(.horizontal, row.3 > 9 ? 4 : 0)
                            .background(AppTheme.primary, in: Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .nwSelectionChrome(isSelected: fixtureSelected == index, cornerRadius: 10)
    }

    private var chat: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                collageAvatar(
                    assets: groups[fixtureSelected].4,
                    size: 48
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("产品研究协作组 · 6人")
                        .font(.headline)
                    Text("产品研究与方案讨论")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: -6) {
                        ForEach(["AvatarZhangMo", "AvatarLinXia", "AvatarFangZhou", "AvatarChenShu"], id: \.self) { asset in
                            Image(asset)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 24, height: 24)
                                .clipShape(Circle())
                                .overlay { Circle().strokeBorder(Color.white, lineWidth: 1.5) }
                        }
                        Button {} label: {
                            Image(systemName: "plus")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 24)
                                .background(AppTheme.surfaceLow, in: Circle())
                                .overlay { Circle().strokeBorder(AppTheme.outlineVariant, lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 8)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 14) {
                    Image(systemName: "magnifyingglass")
                    Image(systemName: "list.bullet")
                    Image(systemName: "ellipsis")
                }
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppTheme.surface)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("昨天 10:15")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)

                    groupMessage(
                        name: "张明",
                        time: "10:15",
                        asset: "AvatarZhangMo",
                        text: "大家早上好，更新一下我们这周的研究进展和后续计划。"
                    )

                    groupMessage(
                        name: "李想",
                        time: "10:17",
                        asset: "AvatarLinXia",
                        text: "我这边把竞品对比分析整理好了，可以先看这版服务卡。"
                    ) {
                        serviceCard
                    }

                    groupMessage(
                        name: "张明",
                        time: "10:24",
                        asset: "AvatarZhangMo",
                        text: "框架图也同步更新了，评审时一起过。"
                    ) {
                        fileCard
                    }

                    groupMessage(
                        name: "孙悦",
                        time: "10:28",
                        asset: "AvatarFangZhou",
                        text: "收到，我补充一版交互注释。"
                    ) {
                        Text("👍 1")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.surfaceLow, in: Capsule())
                    }
                }
                .padding(16)
            }
            .background(AppTheme.surfaceLow.opacity(0.35))

            Divider()
            groupComposer
        }
    }

    private func groupMessage<Content: View>(
        name: String,
        time: String,
        asset: String,
        text: String,
        @ViewBuilder extra: () -> Content = { EmptyView() }
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(asset)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.onSurface)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppTheme.bubbleIncoming, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                    }
                extra()
            }
        }
    }

    private var serviceCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("竞品对比分析")
                        .font(.subheadline.weight(.semibold))
                    Text("服务")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.openStatus, in: Capsule())
                }
                Text("九木服务 · v1.2.0")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
        }
    }

    private var fileCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.richtext.fill")
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color(red: 0.95, green: 0.55, blue: 0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("产品研究-服务框架图.drawio")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("256 KB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
        }
    }

    private var groupComposer: some View {
        HStack(spacing: 8) {
            composerIcon("plus")
            composerIcon("doc.text")
            TextField("输入消息…", text: $draft)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                }
            messagesSolidSendButton(title: "发送") { draft = "" }
        }
        .padding(12)
        .background(AppTheme.surface)
    }

    private func composerIcon(_ systemImage: String) -> some View {
        Button {} label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var inspector: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                infoTabButton("群信息", index: 0)
                infoTabButton("群设置", index: 1)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if infoTab == 0 {
                        groupInfoTabContent
                    } else {
                        groupSettingsTabContent
                    }
                }
                .padding(16)
            }
        }
        .onChange(of: selectedMerge?.id) { _, _ in
            syncMuteFromSelectedMerge()
        }
        .onAppear { syncMuteFromSelectedMerge() }
    }

    @ViewBuilder
    private var groupInfoTabContent: some View {
        if useStaticFixtures {
            Text("成员 (6)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 10) {
                ForEach(members, id: \.0) { member in
                    HStack(spacing: 10) {
                        Image(member.3)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(member.0)
                                    .font(.subheadline.weight(.semibold))
                                if let role = member.2 {
                                    Text(role)
                                        .font(.caption2.bold())
                                        .foregroundStyle(AppTheme.primary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(AppTheme.softPrimary, in: Capsule())
                                }
                            }
                            Text(member.1)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        } else {
            let liveMembers = selectedMerge?.members ?? []
            Text("成员 (\(liveMembers.count))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if liveMembers.isEmpty {
                Text("暂无成员信息")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(liveMembers, id: \.userId) { member in
                        HStack(spacing: 10) {
                            NWAvatarView(
                                url: member.avatarMediaURL,
                                name: member.displayName,
                                size: 32
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Text(member.userId)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }

        Divider()
        if useStaticFixtures {
            Text("关联需求")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("用户画像与核心场景梳理")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text("REQ-2024-1027")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .ninewoodCard()
        }

        Text(useStaticFixtures ? "共享文件 (3)" : "共享文件 (\(displaySharedFiles.count))")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        if displaySharedFiles.isEmpty {
            Text("暂无共享文件")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 10) {
                ForEach(displaySharedFiles, id: \.0) { file in
                    HStack(spacing: 10) {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(file.2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.0)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text(file.1)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        if !useStaticFixtures, let merge = selectedMerge {
            Button {
                showAddMembers = true
            } label: {
                Label("添加成员", systemImage: "person.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .sheet(isPresented: $showAddMembers) {
                AddMergeMembersSheet(mergeId: merge.id) { updated in
                    if let idx = merges.firstIndex(where: { $0.id == updated.id }) {
                        merges[idx] = updated
                    }
                    selectedMerge = updated
                }
                .frame(minWidth: 420, minHeight: 360)
            }
        }
    }

    @ViewBuilder
    private var groupSettingsTabContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("通知")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Toggle("消息免打扰", isOn: $muteNotifications)
                .font(.subheadline)
                .disabled(useStaticFixtures || selectedMerge == nil)
                .onChange(of: muteNotifications) { _, muted in
                    guard !useStaticFixtures, let merge = selectedMerge else { return }
                    Task { await setMute(mergeId: merge.id, muted: muted) }
                }
        }

        Divider()

        VStack(alignment: .leading, spacing: 8) {
            Text("群聊")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Button {
                guard !useStaticFixtures, let merge = selectedMerge else { return }
                Task { await leaveGroup(mergeId: merge.id) }
            } label: {
                Text("退出群聊")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.error)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        Color.white,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(useStaticFixtures || selectedMerge == nil)
        }
    }

    private var displaySharedFiles: [(String, String, Color)] {
        useStaticFixtures ? sharedFiles : liveSharedFiles
    }

    private var filteredLiveBubbles: [ChatBubbleKind] {
        let q = chatSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return liveBubbles }
        return liveBubbles.filter { bubble in
            switch bubble {
            case .system(let text), .time(let text):
                return text.localizedCaseInsensitiveContains(q)
            case .text(let text, _, _):
                return text.localizedCaseInsensitiveContains(q)
            case .card(let card, _):
                return card.title.localizedCaseInsensitiveContains(q)
                    || (card.summary?.localizedCaseInsensitiveContains(q) ?? false)
            }
        }
    }

    private func syncMuteFromSelectedMerge() {
        guard !useStaticFixtures,
              let myId = session.currentUserId ?? session.currentUser?.id,
              let member = selectedMerge?.members?.first(where: { $0.userId == myId })
        else {
            muteNotifications = false
            return
        }
        muteNotifications = member.mutedAt != nil
    }

    private func memberDisplayName(_ member: MergeChatMemberDTO) -> String {
        member.displayName
    }

    private func setMute(mergeId: String, muted: Bool) async {
        do {
            try await session.messageService.muteMerge(id: mergeId, muted: muted)
        } catch {
            liveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            muteNotifications = !muted
        }
    }

    private func leaveGroup(mergeId: String) async {
        do {
            try await session.messageService.leaveMerge(id: mergeId)
            merges.removeAll { $0.id == mergeId }
            if selectedMerge?.id == mergeId {
                selectedMerge = merges.first
            }
            await onRefreshMerges()
        } catch {
            liveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadSharedFiles(mergeId: String) async {
        guard !useStaticFixtures else { return }
        do {
            let rows = try await session.messageService.mergeFiles(id: mergeId)
            liveSharedFiles = rows.compactMap { msg in
                let url = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard url.hasPrefix("http") || url.hasPrefix("/uploads/") else { return nil }
                let name = URL(string: url)?.lastPathComponent ?? url
                return (name, msg.createdAt ?? "", AppTheme.primary)
            }
        } catch {
            liveSharedFiles = []
        }
    }

    private func infoTabButton(_ title: String, index: Int) -> some View {
        Button {
            infoTab = index
        } label: {
            VStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(infoTab == index ? .semibold : .regular))
                    .foregroundStyle(infoTab == index ? AppTheme.primary : Color.secondary)
                Rectangle()
                    .fill(infoTab == index ? AppTheme.primary : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func liveMemberCollage(members: [MergeChatMemberDTO], size: CGFloat) -> some View {
        let cell = (size - 3) / 2
        let slots = Array(members.prefix(4))
        return VStack(spacing: 1) {
            HStack(spacing: 1) {
                liveCollageCell(slots[safe: 0], size: cell)
                liveCollageCell(slots[safe: 1], size: cell)
            }
            HStack(spacing: 1) {
                liveCollageCell(slots[safe: 2], size: cell)
                liveCollageCell(slots[safe: 3], size: cell)
            }
        }
        .frame(width: size, height: size)
        .background(AppTheme.surfaceLow)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    @ViewBuilder
    private func liveCollageCell(_ member: MergeChatMemberDTO?, size: CGFloat) -> some View {
        if let member {
            NWAvatarView(url: member.avatarMediaURL, name: member.displayName, size: size)
                .clipShape(Rectangle())
        } else {
            AppTheme.surfaceLow
                .frame(width: size, height: size)
        }
    }

    private func collageAvatar(assets: [String], size: CGFloat) -> some View {
        let cell = (size - 3) / 2
        return VStack(spacing: 1) {
            HStack(spacing: 1) {
                collageCell(assets[safe: 0], size: cell)
                collageCell(assets[safe: 1], size: cell)
            }
            HStack(spacing: 1) {
                collageCell(assets[safe: 2], size: cell)
                collageCell(assets[safe: 3], size: cell)
            }
        }
        .frame(width: size, height: size)
        .background(AppTheme.surfaceLow)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    @ViewBuilder
    private func collageCell(_ asset: String?, size: CGFloat) -> some View {
        if let asset {
            Image(asset)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipped()
        } else {
            AppTheme.surfaceLow
                .frame(width: size, height: size)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
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
    var onOpened: (() -> Void)? = nil
    @Environment(AppSession.self) private var session
    @State private var model: ChatDetailFeatureModel
    @State private var showCardPicker = false
    @State private var isExtendingCommunication = false
    @State private var openedDemandID: String?
    @State private var openedServiceCardID: String?
    @State private var cardOpenError: String?
    @State private var dmPhotoItem: PhotosPickerItem?

    init(
        thread: ChatThread,
        repository: MessageRepository,
        currentUserID: String,
        previewBubbles: [ChatBubbleKind]? = nil,
        onOpened: (() -> Void)? = nil
    ) {
        _model = State(
            initialValue: ChatDetailFeatureModel(
                thread: thread,
                currentUserID: currentUserID,
                repository: repository,
                previewBubbles: previewBubbles
            )
        )
        self.onOpened = onOpened
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                NWAvatarView(
                    url: model.thread.peer.avatarMediaURL,
                    name: model.thread.peer.name,
                    size: 34
                )
                Text(model.thread.peer.name).font(.headline)
                if let communication = model.thread.communication {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        NWStatusChip(text: communication.remainingText(at: context.date))
                    }
                    if communication.canExtend {
                        Button(isExtendingCommunication ? "延长中…" : "延长 5 分钟") {
                            Task { await extendCommunication() }
                        }
                        .buttonStyle(.borderless)
                        .disabled(isExtendingCommunication)
                    }
                }
                Spacer()
                if let title = model.thread.relatedDemandTitle {
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
                        if model.isLoading && model.bubbles.isEmpty {
                            ProgressView().padding(.top, 40)
                        }
                        ForEach(Array(model.bubbles.enumerated()), id: \.offset) { index, bubble in
                            bubbleView(bubble).id(index)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: model.bubbles.count) { _, _ in
                    if let last = model.bubbles.indices.last {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }

            Divider()
            HStack(spacing: 12) {
                Button {
                    showCardPicker = true
                } label: {
                    Image(systemName: "paperclip")
                }
                .buttonStyle(.bordered)
                .help(model.canAttachMedia ? "发送我的需求卡或服务卡" : "当前不可发送附件")
                .disabled(!model.canAttachMedia)

                PhotosPicker(selection: $dmPhotoItem, matching: .images) {
                    Image(systemName: "photo")
                }
                .buttonStyle(.bordered)
                .help(model.canAttachMedia ? "发送图片" : "当前不可发送附件")
                .disabled(!model.canAttachMedia)

                TextField("发送消息…", text: $model.draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await model.send() } }
                Button {
                    Task { await model.send() }
                } label: {
                    if model.isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSend)
            }
            .padding(12)
        }
        .background(AppTheme.workspaceBackground)
        .task {
            onOpened?()
            await model.load()
            await session.refreshUnread()
        }
        .onChange(of: dmPhotoItem) { _, item in
            guard let item else { return }
            Task {
                await sendDirectPhoto(item)
                dmPhotoItem = nil
            }
        }
        .onChange(of: session.chatRealtime.lastIncoming) { _, incoming in
            guard let incoming else { return }
            if incoming.hasCardAttachment {
                Task { await model.load() }
            } else {
                model.appendRealtime(incoming)
            }
        }
        .sheet(isPresented: $showCardPicker) {
            MessageCardPicker { type, id in
                showCardPicker = false
                Task { await model.sendCard(type: type, cardID: id) }
            }
            .environment(session)
            .frame(minWidth: 520, minHeight: 460)
        }
        .sheet(item: Binding(
            get: { openedDemandID.map(IdentifiableString.init) },
            set: { openedDemandID = $0?.value }
        )) { item in
            NavigationStack {
                DemandDetailLoaderView(demandID: item.value)
            }
            .environment(session)
            .frame(minWidth: 720, minHeight: 640)
        }
        .sheet(item: Binding(
            get: { openedServiceCardID.map(IdentifiableString.init) },
            set: { openedServiceCardID = $0?.value }
        )) { item in
            NavigationStack {
                ServiceCardLoaderView(cardID: item.value)
            }
            .environment(session)
            .frame(minWidth: 560, minHeight: 480)
        }
        .alert("发送失败", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("无法打开卡片", isPresented: Binding(
            get: { cardOpenError != nil },
            set: { if !$0 { cardOpenError = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(cardOpenError ?? "")
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
        case .text(let text, let isMine, _):
            if text.hasPrefix("/uploads/") || text.contains("/uploads/") {
                HStack {
                    if isMine { Spacer(minLength: 80) }
                    NWRemoteImage(url: APIConfig.mediaURL(text), cornerRadius: 10)
                        .frame(width: 200, height: 140)
                        .clipped()
                    if !isMine { Spacer(minLength: 80) }
                }
            } else {
                HStack {
                    if isMine { Spacer(minLength: 80) }
                    Text(text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(isMine ? .white : AppTheme.onSurface)
                        .background(isMine ? AppTheme.primary : AppTheme.bubbleIncoming)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    if !isMine { Spacer(minLength: 80) }
                }
            }
        case .card(let card, _):
            HStack {
                if card.isMine { Spacer(minLength: 80) }
                Button {
                    openCard(card)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(
                                card.kind == .demand ? "需求卡" : "服务卡",
                                systemImage: card.kind == .demand ? "doc.text" : "rectangle.stack"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(card.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if let summary = card.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        HStack {
                            if let price = card.price {
                                Text(price.currencyText)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                            if let status = card.status {
                                Spacer()
                                NWStatusChip(text: status)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: 360, alignment: .leading)
                    .background(card.isMine ? AppTheme.primary.opacity(0.12) : AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.fill)
                    )
                }
                .buttonStyle(.plain)
                .disabled(card.cardID == nil || card.kind == .unknown)
                .help(card.cardID == nil ? "缺少卡片 ID，无法打开" : "查看详情")
                if !card.isMine { Spacer(minLength: 80) }
            }
        }
    }

    private func openCard(_ card: ChatCardAttachment) {
        guard let cardID = card.cardID, !cardID.isEmpty else {
            cardOpenError = "这条卡片消息缺少可打开的业务 ID"
            return
        }
        switch card.kind {
        case .demand:
            openedDemandID = cardID
        case .serviceCard:
            openedServiceCardID = cardID
        case .unknown:
            cardOpenError = "暂不支持打开此类卡片"
        }
    }

    private func extendCommunication() async {
        guard let communication = model.thread.communication else { return }
        isExtendingCommunication = true
        defer { isExtendingCommunication = false }
        do {
            let updated = try await session.demandRepository.extendCommunication(
                demandID: communication.demandID,
                applicantID: communication.applicantID,
                minutes: 5
            )
            model.updateCommunication(
                deadline: APIDate.parse(updated.commDeadline),
                addedMinutes: 5
            )
        } catch {
            model.errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func sendDirectPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                model.errorMessage = "无法读取所选图片"
                return
            }
            await model.sendImage(
                data: data,
                fileName: "dm_\(Int(Date().timeIntervalSince1970)).jpg",
                mimeType: "image/jpeg"
            )
        } catch {
            model.errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

enum MessagesDesignPreviewFixtures {
    static let users: [AppUser] = [
        AppUser(id: "u-linxia", name: "林夏", avatarUrl: nil, coverUrl: nil, demandCardCoverUrl: nil, creditScore: 86, completedOrders: 23, goodRate: 0.98),
        AppUser(id: "u-chengye", name: "程野", avatarUrl: nil, coverUrl: nil, demandCardCoverUrl: nil, creditScore: 82, completedOrders: 17, goodRate: 0.96),
        AppUser(id: "u-zhouzhou", name: "周舟", avatarUrl: nil, coverUrl: nil, demandCardCoverUrl: nil, creditScore: 78, completedOrders: 12, goodRate: 0.94),
        AppUser(id: "u-xiaomu", name: "小木助手", avatarUrl: nil, coverUrl: nil, demandCardCoverUrl: nil, creditScore: 100, completedOrders: 0, goodRate: 1)
    ]

    static let threads: [ChatThread] = [
        ChatThread(
            id: "thread-1",
            peer: users[0],
            preview: "好的，我看看这个需求卡，稍后给你反馈。",
            timeText: "14:32",
            unreadCount: 2,
            relatedDemandTitle: "智能耳机用户研究",
            isCommunicating: true,
            isSystem: false,
            remainingCommText: "沟通资格剩余 03:42",
            communication: CommunicationContext(
                applicantID: "applicant-1",
                demandID: "demand-1",
                demandTitle: "智能耳机用户研究",
                deadline: Date().addingTimeInterval(3 * 60 + 42),
                canExtend: true,
                extensionMinutes: 0
            )
        ),
        ChatThread(id: "thread-2", peer: users[1], preview: "明天下午可以开始第一次访谈。", timeText: "13:05", unreadCount: 0, relatedDemandTitle: "用户访谈记录整理", isCommunicating: false, isSystem: false, remainingCommText: nil),
        ChatThread(id: "thread-3", peer: users[2], preview: "需求卡已更新", timeText: "昨天", unreadCount: 0, relatedDemandTitle: "竞品功能体验报告", isCommunicating: false, isSystem: false, remainingCommText: nil),
        ChatThread(id: "thread-4", peer: users[3], preview: "你的订单已进入验收阶段", timeText: "周一", unreadCount: 1, relatedDemandTitle: nil, isCommunicating: false, isSystem: true, remainingCommText: nil)
    ]

    static let bubbles: [ChatBubbleKind] = [
        .time("14:12"),
        .system("对方已通过真实身份认证，可放心沟通"),
        .text("你好，我看到你在做消费电子方向的产品研究，想咨询一下有没有档期可以接一个小需求？", isMine: false, sender: nil),
        .text("你好，感谢关注！可以的，请先发一下需求详情和预期时间哈。", isMine: true, sender: nil),
        .text("好的，我整理了一下需求卡，麻烦帮忙看看～", isMine: false, sender: nil),
        .text("好的，我看看这个需求卡，稍后给你反馈。", isMine: true, sender: nil),
        .time("14:32"),
        .card(ChatCardAttachment(
            id: "card-1",
            kind: .demand,
            cardID: "demand-1",
            title: "智能耳机用户研究",
            summary: "需求方：林夏（已认证）· 预算 600 点 · 2025-05-31 前",
            price: 600,
            status: "待确认",
            coverImage: nil,
            isMine: false
        ), sender: nil)
    ]

    static let merges: [MergeChatDTO] = [
        MergeChatDTO(
            id: "preview-merge-1",
            title: "智能硬件研究协作组",
            userId: "preview-requester",
            members: [
                MergeChatMemberDTO(id: "member-1", userId: "u-linxia", mergeId: "preview-merge-1", createdAt: nil),
                MergeChatMemberDTO(id: "member-2", userId: "u-chengye", mergeId: "preview-merge-1", createdAt: nil),
                MergeChatMemberDTO(id: "member-3", userId: "u-zhouzhou", mergeId: "preview-merge-1", createdAt: nil),
                MergeChatMemberDTO(id: "member-4", userId: "preview-requester", mergeId: "preview-merge-1", createdAt: nil)
            ],
            createdAt: "2026-07-16T09:00:00Z",
            updatedAt: "2026-07-18T14:28:00Z"
        ),
        MergeChatDTO(
            id: "preview-merge-2",
            title: "品牌升级交付群",
            userId: "preview-requester",
            members: [
                MergeChatMemberDTO(id: "member-5", userId: "u-linxia", mergeId: "preview-merge-2", createdAt: nil),
                MergeChatMemberDTO(id: "member-6", userId: "preview-requester", mergeId: "preview-merge-2", createdAt: nil)
            ],
            createdAt: "2026-07-15T09:00:00Z",
            updatedAt: "2026-07-17T16:20:00Z"
        )
    ]

    static let mergeBubbles: [ChatBubbleKind] = [
        .time("今天 14:12"),
        .system("林夏邀请程野加入群聊"),
        .text("访谈提纲已经更新，重点补充了购买决策和售后体验。", isMine: false, sender: nil),
        .text("收到，我会按新版提纲完成明天的两场访谈。", isMine: false, sender: nil),
        .card(ChatCardAttachment(
            id: "preview-merge-card",
            kind: .demand,
            cardID: "demand-1",
            title: "智能硬件产品用户研究",
            summary: "6 位目标用户访谈与洞察优先级",
            price: 600,
            status: "沟通中",
            coverImage: nil,
            isMine: true
        ), sender: nil),
        .text("辛苦，完成后把原始记录和洞察摘要一起发到群里。", isMine: true, sender: nil)
    ]
}

private struct MessageCardPicker: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let onSelect: (ChatCardAttachment.Kind, String) -> Void

    @State private var demands: [Demand] = []
    @State private var serviceCards: [ServiceCardDTO] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && demands.isEmpty && serviceCards.isEmpty {
                    ProgressView("加载可发送卡片…")
                } else if let errorMessage, demands.isEmpty && serviceCards.isEmpty {
                    NWEmptyState(
                        title: "卡片加载失败",
                        systemImage: "wifi.exclamationmark",
                        message: errorMessage
                    )
                } else {
                    List {
                        Section("我的需求") {
                            ForEach(demands) { demand in
                                Button {
                                    onSelect(.demand, demand.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(demand.title)
                                        Text(demand.minPrice.currencyText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Section("我的服务卡") {
                            ForEach(serviceCards) { card in
                                Button {
                                    onSelect(.serviceCard, card.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(card.title)
                                        Text(card.summary ?? card.description ?? "服务卡")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("发送卡片")
            .toolbar {
                Button("取消") { dismiss() }
            }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let demandTask = session.demandRepository.mine()
            async let cardTask = session.serviceCardService.mine()
            let (allDemands, allCards) = try await (demandTask, cardTask)
            // 服务端需求卡要求本人公开需求；草稿/冻结不可发。
            demands = allDemands.filter { $0.status == .active }
            serviceCards = allCards
            if demands.isEmpty && serviceCards.isEmpty {
                errorMessage = "暂无可发送卡片。请先发布公开需求，或创建并保存服务卡。"
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

private struct ChatCardAttachmentChip: View {
    let attachment: ChatCardAttachment

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: attachment.kind == .demand ? "doc.text.fill" : "rectangle.stack.fill")
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(attachment.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if let summary = attachment.summary, !summary.isEmpty, summary != attachment.title {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(10)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
        }
    }
}

private struct IdentifiableString: Identifiable, Hashable {
    let value: String
    var id: String { value }
}

struct DemandDetailLoaderView: View {
    let demandID: String
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var demand: Demand?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let demand {
                DemandDetailView(demand: demand)
            } else if let errorMessage {
                NWEmptyState(
                    title: "需求加载失败",
                    systemImage: "wifi.exclamationmark",
                    message: errorMessage
                )
            } else {
                ProgressView("加载需求详情…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
        .task {
            do {
                demand = try await session.demandRepository.detail(id: demandID)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }
}

struct ServiceCardLoaderView: View {
    let cardID: String
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var card: ServiceCardDTO?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let card {
                ServiceCardPublicDetailView(card: card)
            } else if let errorMessage {
                NWEmptyState(
                    title: "服务卡加载失败",
                    systemImage: "wifi.exclamationmark",
                    message: errorMessage
                )
            } else {
                ProgressView("加载服务卡…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
        .task {
            do {
                card = try await session.serviceCardService.get(id: cardID)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }
}

struct ServiceCardPublicDetailView: View {
    let card: ServiceCardDTO

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(card.title).font(.title.bold())
                if let status = card.status {
                    NWStatusChip(text: status)
                }
                if let publisher = card.publisher {
                    Text(publisher.nickname ?? "服务方")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(card.description ?? card.summary ?? "")
                    .foregroundStyle(.secondary)
                if let tags = card.tags, !tags.isEmpty {
                    Text(tags.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    if let min = card.priceMin?.value {
                        Text("起价 \(min.currencyText)")
                            .font(.headline)
                    }
                    if let max = card.priceMax?.value {
                        Text("— \(max.currencyText)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(AppTheme.horizontalPadding)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .background(AppTheme.workspaceBackground)
        .navigationTitle("服务卡")
    }
}

private struct MergeChatDetailView: View {
    let merge: MergeChatDTO
    let previewBubbles: [ChatBubbleKind]?
    @Environment(AppSession.self) private var session
    @State private var bubbles: [ChatBubbleKind] = []
    @State private var draft = ""
    @State private var isLoading = false
    @State private var isSending = false
    @State private var errorMessage: String?

    init(merge: MergeChatDTO, previewBubbles: [ChatBubbleKind]? = nil) {
        self.merge = merge
        self.previewBubbles = previewBubbles
        _bubbles = State(initialValue: previewBubbles ?? [])
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(merge.displayTitle).font(.headline)
                NWStatusChip(text: "\(merge.memberCount) 人")
                Spacer()
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
                            mergeBubbleView(bubble).id(index)
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
                TextField("发送群聊消息…", text: $draft)
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
        .task(id: merge.id) { await load() }
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
    private func mergeBubbleView(_ bubble: ChatBubbleKind) -> some View {
        switch bubble {
        case .system(let text), .time(let text):
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        case .text(let text, let isMine, _):
            HStack {
                if isMine { Spacer(minLength: 80) }
                Text(text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(isMine ? .white : AppTheme.onSurface)
                    .background(isMine ? AppTheme.primary : AppTheme.bubbleIncoming)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                if !isMine { Spacer(minLength: 80) }
            }
        case .card(let card, _):
            HStack {
                if card.isMine { Spacer(minLength: 80) }
                VStack(alignment: .leading, spacing: 6) {
                    Text(card.kind == .demand ? "需求卡" : "服务卡")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(card.title).font(.headline)
                }
                .padding(12)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                if !card.isMine { Spacer(minLength: 80) }
            }
        }
    }

    private func load() async {
        if let previewBubbles {
            bubbles = previewBubbles
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            bubbles = try await session.messageRepository.mergeMessages(
                mergeID: merge.id,
                currentUserID: session.currentUserId ?? ""
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func send() async {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await session.messageRepository.sendMergeMessage(mergeID: merge.id, content: content)
            draft = ""
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

private struct AddMergeMembersSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let mergeId: String
    let onUpdated: (MergeChatDTO) -> Void

    @State private var contacts: [SoftUserDTO] = []
    @State private var selectedIDs: Set<String> = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("从关注列表添加") {
                    if isLoading && contacts.isEmpty {
                        ProgressView()
                    } else if contacts.isEmpty {
                        Text("暂无关注用户").foregroundStyle(.secondary)
                    } else {
                        ForEach(contacts) { user in
                            Toggle(isOn: Binding(
                                get: { selectedIDs.contains(user.id) },
                                set: { on in
                                    if on { selectedIDs.insert(user.id) }
                                    else { selectedIDs.remove(user.id) }
                                }
                            )) {
                                Text(user.nickname ?? "用户")
                            }
                        }
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppTheme.error)
                }
            }
            .navigationTitle("添加成员")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "添加中…" : "添加") {
                        Task { await save() }
                    }
                    .disabled(selectedIDs.isEmpty || isSaving)
                }
            }
            .task { await loadContacts() }
        }
    }

    private func loadContacts() async {
        guard let myId = session.currentUserId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            contacts = try await session.userService.following(id: myId)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await session.messageService.addMergeMembers(
                id: mergeId,
                userIds: Array(selectedIDs)
            )
            onUpdated(updated)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct CreateMergeChatSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let onCreated: (MergeChatDTO) -> Void

    @State private var title = ""
    @State private var contacts: [SoftUserDTO] = []
    @State private var selectedIDs: Set<String> = []
    @State private var isLoading = false
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("群聊名称", text: $title)
                Section("选择联系人（关注列表）") {
                    if isLoading && contacts.isEmpty {
                        ProgressView()
                    } else if contacts.isEmpty {
                        Text("暂无关注用户，请先去关注联系人")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(contacts) { user in
                            Toggle(isOn: Binding(
                                get: { selectedIDs.contains(user.id) },
                                set: { on in
                                    if on { selectedIDs.insert(user.id) }
                                    else { selectedIDs.remove(user.id) }
                                }
                            )) {
                                Text(user.nickname ?? "用户")
                            }
                        }
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppTheme.error)
                }
            }
            .navigationTitle("新建群聊")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? "创建中…" : "创建") {
                        Task { await create() }
                    }
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || selectedIDs.isEmpty
                            || isCreating
                    )
                }
            }
            .task { await loadContacts() }
        }
    }

    private func loadContacts() async {
        guard let myId = session.currentUserId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            contacts = try await session.userService.following(id: myId)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        do {
            let created = try await session.messageRepository.createMerge(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                memberIds: Array(selectedIDs)
            )
            onCreated(created)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
