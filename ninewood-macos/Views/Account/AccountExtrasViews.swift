import SwiftUI

struct FollowsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case following = "关注"
        case followers = "粉丝"
        var id: String { rawValue }
    }

    @Environment(AppSession.self) private var session
    @State private var tab: Tab = .following
    @State private var users: [SoftUserDTO] = []
    @State private var selected: SoftUserDTO?
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                NWPaneCaption(text: "关注与粉丝")
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

                if isLoading && users.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 32)
                    Spacer(minLength: 0)
                } else if let loadError, users.isEmpty {
                    NWEmptyState(title: "加载失败", systemImage: "wifi.exclamationmark", message: loadError)
                    Spacer(minLength: 0)
                } else if users.isEmpty {
                    NWEmptyState(title: "列表为空", systemImage: "person.2", message: "去「找人」关注感兴趣的用户")
                    Spacer(minLength: 0)
                } else {
                    List(users, selection: $selected) { user in
                        HStack(spacing: 10) {
                            NWAvatarView(
                                url: user.avatarMediaURL,
                                name: user.nickname ?? "用户",
                                size: 36
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.nickname ?? "用户")
                                    .font(.body.weight(.semibold))
                                Text("信用 \(user.creditScore ?? 60)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(user)
                    }
                    .listStyle(.inset)
                }
            }
            .paneColumn(minWidth: 280, idealWidth: 320)

            Divider()
            Group {
                if let selected {
                    UserProfileView(userId: selected.id)
                } else {
                    NWDetailPlaceholder(title: "选择用户", systemImage: "person")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("关注")
        .task(id: tab) { await load() }
    }

    private func load() async {
        guard let myId = session.currentUserId else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            switch tab {
            case .following:
                users = try await session.userService.following(id: myId)
            case .followers:
                users = try await session.userService.followers(id: myId)
            }
            selected = users.first
        } catch {
            users = []
            selected = nil
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct FavoritesView: View {
    @Environment(AppSession.self) private var session
    @State private var demands: [Demand] = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NWPaneCaption(text: "收藏的需求")
            if isLoading && demands.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                Spacer()
            } else if let loadError, demands.isEmpty {
                NWEmptyState(title: "收藏加载失败", systemImage: "wifi.exclamationmark", message: loadError)
                Spacer()
            } else if demands.isEmpty {
                NWEmptyState(title: "暂无收藏", systemImage: "star", message: "在需求详情可收藏")
                Spacer()
            } else {
                List(demands) { demand in
                    NavigationLink { DemandDetailView(demand: demand) } label: {
                        DemandRowView(demand: demand)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.workspaceBackground)
        .navigationTitle("收藏")
        .task { await load() }
        .toolbar { Button("刷新") { Task { await load() } } }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let page = try await session.userService.favorites()
            demands = page.demands.map(DemandMapper.mapListItem)
        } catch {
            demands = []
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct NotificationsView: View {
    @Environment(AppSession.self) private var session
    @State private var items: [NotificationDTO] = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NWPaneCaption(text: "系统与业务通知")
            if isLoading && items.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 32)
                Spacer()
            } else if let loadError, items.isEmpty {
                NWEmptyState(title: "通知加载失败", systemImage: "wifi.exclamationmark", message: loadError)
                Spacer()
            } else if items.isEmpty {
                NWEmptyState(title: "暂无通知", systemImage: "bell", message: "有新动态时会出现在这里")
                Spacer()
            } else {
                List(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title ?? item.type ?? "通知").font(.headline)
                        Text(item.content ?? "").font(.subheadline).foregroundStyle(.secondary)
                        Text(item.createdAt ?? "").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.workspaceBackground)
        .navigationTitle("通知")
        .task { await load() }
        .toolbar {
            Button("刷新") { Task { await load() } }
        }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            items = try await session.messageService.notifications()
        } catch {
            items = []
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct ProvidersSearchView: View {
    @Environment(AppSession.self) private var session
    @State private var tagQuery = ""
    @State private var users: [SoftUserDTO] = []
    @State private var selected: SoftUserDTO?
    @State private var isLoading = false
    @State private var searchError: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                NWPaneCaption(text: "按标签检索")
                HStack {
                    NWSearchBar(text: $tagQuery, placeholder: "例如：水电维修") {
                        Task { await search() }
                    }
                    Button("搜索") { Task { await search() } }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 32)
                    Spacer(minLength: 0)
                } else if let searchError, users.isEmpty {
                    NWEmptyState(title: "检索失败", systemImage: "wifi.exclamationmark", message: searchError)
                    Spacer(minLength: 0)
                } else if users.isEmpty {
                    NWEmptyState(title: "输入标签搜索", systemImage: "person.badge.shield.checkmark", message: "查找认证服务者")
                    Spacer(minLength: 0)
                } else {
                    List(users, selection: $selected) { user in
                        HStack(spacing: 10) {
                            NWAvatarView(
                                url: user.avatarMediaURL,
                                name: user.nickname ?? "用户",
                                size: 36
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.nickname ?? "用户").font(.body.weight(.semibold))
                                Text("信用 \(user.creditScore ?? 60)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(user)
                    }
                    .listStyle(.inset)
                }
            }
            .paneColumn(minWidth: 300, idealWidth: 340)

            Divider()
            Group {
                if let selected {
                    UserProfileView(userId: selected.id)
                } else {
                    NWDetailPlaceholder(title: "选择服务者", systemImage: "checkmark.shield")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("认证检索")
    }

    private func search() async {
        let q = tagQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isLoading = true
        searchError = nil
        defer { isLoading = false }
        do {
            users = try await session.certificationService.providers(tags: q)
            selected = users.first
        } catch {
            do {
                users = try await session.userService.searchByTags(q)
                selected = users.first
            } catch {
                users = []
                selected = nil
                searchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

struct WelfareCenterView: View {
    @Environment(AppSession.self) private var session
    @State private var items: [WelfareItemDTO] = []
    @State private var message: String?
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NWPaneCaption(text: "公益与奖励任务")
            if isLoading && items.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 32)
                Spacer()
            } else if let loadError, items.isEmpty {
                NWEmptyState(title: "福利加载失败", systemImage: "wifi.exclamationmark", message: loadError)
                Spacer()
            } else if items.isEmpty {
                NWEmptyState(title: "暂无福利任务", systemImage: "gift", message: "有可用福利时会出现在这里")
                Spacer()
            } else {
                List(items) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.title ?? "福利").font(.headline)
                            Text(item.description ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("领取") {
                            Task {
                                do {
                                    try await session.welfareService.claim(demandId: item.id)
                                    message = "已领取"
                                } catch {
                                    message = error.localizedDescription
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.workspaceBackground)
        .navigationTitle("福利")
        .task { await load() }
        .toolbar { Button("刷新") { Task { await load() } } }
        .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("确定", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            items = try await session.welfareService.list()
        } catch {
            items = []
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var nickname = ""
    @State private var bio = ""
    @State private var isBusy = false
    @State private var myTags: [String] = []
    @State private var tagDraft = ""
    @State private var blockTags = ""
    @State private var blockKeywords = ""
    @State private var message: String?

    var body: some View {
        DocumentShell {
            VStack(alignment: .leading, spacing: AppTheme.space24) {
                
                section("资料") {
                    TextField("昵称", text: $nickname).textFieldStyle(.roundedBorder)
                    TextField("简介", text: $bio).textFieldStyle(.roundedBorder)
                    Button("保存资料") { Task { await saveProfile() } }
                        .buttonStyle(.borderedProminent)
                }

                section("忙碌状态") {
                    Toggle("忙碌中（减少推送）", isOn: $isBusy)
                        .onChange(of: isBusy) { _, value in
                            Task { await saveBusy(value) }
                        }
                }

                section("我的标签") {
                    Text(myTags.isEmpty ? "尚未设置" : myTags.joined(separator: "、"))
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("新标签", text: $tagDraft).textFieldStyle(.roundedBorder)
                        Button("添加") {
                            let t = tagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !t.isEmpty else { return }
                            myTags.append(t)
                            tagDraft = ""
                            Task { await saveTags() }
                        }
                    }
                }

                section("推送屏蔽") {
                    TextField("屏蔽标签（逗号分隔）", text: $blockTags).textFieldStyle(.roundedBorder)
                    TextField("屏蔽关键词（逗号分隔）", text: $blockKeywords).textFieldStyle(.roundedBorder)
                    Button("保存屏蔽") { Task { await saveBlocklist() } }
                }

                section("关于") {
                    LabeledContent("API", value: APIConfig.baseURL.absoluteString)
                    LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    NavigationLink("隐私政策") { LegalDocView(kind: .privacy) }
                    NavigationLink("用户协议") { LegalDocView(kind: .terms) }
                    NavigationLink("开源许可") { LegalDocView(kind: .licenses) }
                }

                if let message {
                    Text(message).foregroundStyle(AppTheme.openStatus)
                }
            }
        }
        .navigationTitle("设置")
        .task { await load() }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .padding(16)
        .ninewoodCard()
    }

    private func load() async {
        nickname = session.currentUser?.nickname ?? ""
        do {
            let me = try await session.userService.me()
            bio = me.bio ?? ""
            nickname = me.nickname ?? nickname
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        do {
            myTags = try await session.userService.myTags()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        do {
            let busy = try await session.userService.busyStatus()
            isBusy = busy.isBusy ?? false
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        do {
            let bl = try await session.userService.fetchBlocklist()
            blockTags = bl.tags.joined(separator: ",")
            blockKeywords = bl.keywords.joined(separator: ",")
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func saveProfile() async {
        do {
            _ = try await session.userService.updateProfile(
                nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
                bio: bio.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            message = "资料已保存"
            await session.retryBootstrap()
        } catch {
            message = error.localizedDescription
        }
    }

    private func saveBlocklist() async {
        let tags = blockTags.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let keywords = blockKeywords.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        do {
            try await session.userService.updateBlocklist(tags: tags, keywords: keywords)
            message = "屏蔽规则已保存"
        } catch {
            message = error.localizedDescription
        }
    }

    private func saveBusy(_ value: Bool) async {
        do {
            try await session.userService.updateBusy(isBusy: value)
        } catch {
            message = error.localizedDescription
            isBusy = !value
        }
    }

    private func saveTags() async {
        do {
            try await session.userService.updateTags(myTags)
            message = "标签已更新"
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct LegalDocView: View {
    enum Kind {
        case privacy, terms, licenses
        var title: String {
            switch self {
            case .privacy: "隐私政策"
            case .terms: "用户协议"
            case .licenses: "开源许可"
            }
        }
    }

    let kind: Kind

    var body: some View {
        DocumentShell(maxWidth: AppTheme.documentWideMaxWidth) {
            Text(bodyText)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .navigationTitle(kind.title)
    }

    private var bodyText: String {
        switch kind {
        case .privacy:
            """
            九木（Ninewood）重视你的隐私。我们仅收集提供服务所必需的信息，包括账号手机号、资料、交易与沟通记录，以及设备与日志信息用于安全与排障。

            数据用途：身份验证、需求匹配、订单托管与结算、消息推送、风控与客服。我们不会向无关第三方出售个人数据。

            你可在「设置」中更新资料与屏蔽规则；如需注销或导出数据，请联系平台支持。完整条款以 tothetomorrow.com 公示版本为准。
            """
        case .terms:
            """
            使用九木即表示你同意：如实发布需求与服务信息；不得利用平台从事违法、欺诈或骚扰行为；交易资金经平台点数钱包托管与结算，服务费按订单规则收取。

            正式接单前的「请求接单 / 应标」仅用于沟通，不构成合同。验收确认后完成结算；争议由平台依据提交证据调解。

            平台可在合理范围内更新本协议，重大变更将通过应用内通知。继续使用即视为接受更新后的条款。
            """
        case .licenses:
            """
            本应用使用开源组件，包括但不限于 Socket.IO Client Swift、Starscream 等，遵循其各自许可证（MIT 等）。

            九木客户端与服务端代码版权归项目维护者所有。第三方字体与图标资源遵循其来源许可。
            """
        }
    }
}
