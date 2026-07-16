import SwiftUI
import AppKit

struct CirclesView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case publicList = "公开"
        case mine = "我的"
        var id: String { rawValue }
    }

    @Environment(AppSession.self) private var session
    @State private var tab: Tab = .mine
    @State private var circles: [CircleDTO] = []
    @State private var selected: CircleDTO?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var joinCode = ""
    @State private var actionMessage: String?
    @State private var showCreate = false
    @State private var showJoinSheet = false

    var body: some View {
        HStack(spacing: 0) {
            listPane
                .paneColumn(minWidth: 320, idealWidth: 380)

            Divider()

            Group {
                if let selected {
                    CircleDetailView(circle: selected) {
                        Task { await load() }
                    }
                    .id(selected.id)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)).combined(with: .offset(x: 12)),
                        removal: .opacity
                    ))
                } else {
                    NWDetailPlaceholder(
                        title: "选择圈子",
                        systemImage: "person.3",
                        message: "从左侧选择一个圈子查看详情"
                    )
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.36, dampingFraction: 0.9), value: selected?.id)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("圈子")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("邀请码加入") { showJoinSheet = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("创建") { showCreate = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await load() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task(id: tab) { await load() }
        .sheet(isPresented: $showCreate) {
            CreateCircleSheet { created in
                showCreate = false
                selected = created
                tab = .mine
                Task { await load() }
            }
            .frame(minWidth: 420, minHeight: 300)
        }
        .sheet(isPresented: $showJoinSheet) {
            JoinCircleSheet(code: $joinCode) {
                showJoinSheet = false
                Task { await joinByCode() }
            }
            .frame(minWidth: 380, minHeight: 200)
        }
        .alert("圈子", isPresented: Binding(
            get: { actionMessage != nil },
            set: { if !$0 { actionMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(actionMessage ?? "")
        }
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            NWPaneCaption(text: tab == .mine ? "我加入的圈子" : "可浏览的公开圈子")

            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, AppTheme.space16)
            .padding(.bottom, AppTheme.space12)

            if let loadError {
                VStack(alignment: .leading, spacing: AppTheme.space8) {
                    Text(loadError).foregroundStyle(.secondary)
                    Button("重新加载") { Task { await load() } }
                }
                .padding(AppTheme.space16)
                Spacer(minLength: 0)
            } else if isLoading && circles.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                Spacer(minLength: 0)
            } else if circles.isEmpty {
                NWEmptyState(
                    title: tab == .mine ? "还没有加入圈子" : "暂无公开圈子",
                    systemImage: "person.3",
                    message: tab == .mine
                        ? "用邀请码加入，或点击右上角创建。"
                        : "当前没有公开圈子；你加入的在「我的」，也可用邀请码加入。"
                )
                Spacer(minLength: 0)
            } else {
                List(circles, selection: $selected) { circle in
                    CircleRowView(circle: circle)
                        .tag(circle)
                        .listRowInsets(EdgeInsets(
                            top: 8,
                            leading: AppTheme.space12,
                            bottom: 8,
                            trailing: AppTheme.space12
                        ))
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            switch tab {
            case .publicList:
                circles = try await session.circleService.publicCircles()
            case .mine:
                circles = try await session.circleService.myCircles()
            }
            if let selected, circles.contains(where: { $0.id == selected.id }) {
                // keep
            } else {
                self.selected = circles.first
            }
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            circles = []
        }
    }

    private func joinByCode() async {
        let code = joinCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        do {
            try await session.circleService.joinByCode(code)
            joinCode = ""
            actionMessage = "已加入圈子"
            tab = .mine
            await load()
        } catch {
            actionMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct CircleRowView: View {
    let circle: CircleDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(circle.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    if circle.type == "PRIVATE" {
                        NWStatusChip(text: "私密")
                    }
                    Spacer(minLength: 0)
                }

                if let description = circle.description?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: AppTheme.space12) {
                    Label("\(circle.memberCount ?? 0) 成员", systemImage: "person.2")
                    if let role = circle.role {
                        NWStatusChip(text: role)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            cover
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var cover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.fill.opacity(0.45))

            if circle.coverMediaURL != nil {
                NWRemoteImage(
                    url: circle.coverMediaURL,
                    cornerRadius: 10,
                    systemFallback: "person.3",
                    fit: .fill
                )
            } else {
                Text(monogram)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant.opacity(0.7), lineWidth: 1)
        }
    }

    private var monogram: String {
        let name = circle.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = name.first else { return "圈" }
        return String(first)
    }
}

private struct CircleDetailView: View {
    enum HubTab: String, CaseIterable, Identifiable {
        case overview = "概览"
        case members = "成员"
        case resources = "资源"
        case activity = "动态"
        case analytics = "分析"
        case manage = "管理"
        var id: String { rawValue }
    }

    let circle: CircleDTO
    var onJoined: () -> Void
    @Environment(AppSession.self) private var session
    @State private var detail: CircleDTO?
    @State private var hub: CircleHubHomeDTO?
    @State private var members: [CircleMemberDTO] = []
    @State private var resources: [CircleResourceDTO] = []
    @State private var activities: [CircleActivityDTO] = []
    @State private var tab: HubTab = .overview
    @State private var isJoining = false
    @State private var isLoadingHub = false
    @State private var message: String?
    @State private var hubError: String?
    @State private var analytics: CircleAnalyticsDTO?
    @State private var isLoadingAnalytics = false
    @State private var analyticsError: String?
    @State private var annTitle = ""
    @State private var annBody = ""
    @State private var annPinned = false
    @State private var inviteEmail = ""
    @State private var isPostingAnn = false
    @State private var isInviting = false
    @State private var isHeartbeating = false
    @State private var membersError: String?
    @State private var resourcesError: String?
    @State private var activitiesError: String?
    @State private var manageMessage: String?
    @State private var appeared = false

    private var current: CircleDTO { detail ?? circle }

    private var canManage: Bool {
        guard let role = current.role?.uppercased() else { return false }
        return role == "OWNER" || role == "ADMIN"
    }

    private var visibleTabs: [HubTab] {
        canManage ? HubTab.allCases : HubTab.allCases.filter { $0 != .manage }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.space24) {
                header

                Picker("Hub", selection: $tab) {
                    ForEach(visibleTabs) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                switch tab {
                case .overview:
                    overviewSection
                case .members:
                    membersSection
                case .resources:
                    resourcesSection
                case .activity:
                    activitySection
                case .analytics:
                    analyticsSection
                case .manage:
                    manageSection
                }

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(AppTheme.space24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.workspaceBackground)
        .task(id: circle.id) {
            appeared = false
            withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                appeared = true
            }
            tab = .overview
            await loadAll()
        }
        .onChange(of: tab) { _, newTab in
            if newTab == .analytics && analytics == nil && analyticsError == nil {
                Task { await loadAnalytics() }
            }
        }
        .onChange(of: canManage) { _, manage in
            if !manage, tab == .manage {
                tab = .overview
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppTheme.space16) {
            ZStack(alignment: .topLeading) {
                if current.coverMediaURL != nil {
                    NWHeroImage(url: current.coverMediaURL, maxHeight: 280, systemFallback: "person.3")
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.fill.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .frame(height: 140)
                        .overlay {
                            Image(systemName: "person.3")
                                .font(.title)
                                .foregroundStyle(.secondary)
                        }
                }

                NWStatusChip(
                    text: current.type == "PRIVATE" ? "私密" : "公开",
                    tint: current.type == "PRIVATE" ? AppTheme.secondary : AppTheme.openStatus
                )
                .padding(AppTheme.space12)
            }

            VStack(alignment: .leading, spacing: AppTheme.space8) {
                Text(current.name)
                    .font(.title.bold())
                    .fixedSize(horizontal: false, vertical: true)

                Text(current.description ?? "暂无简介")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: AppTheme.space12) {
                    Label("\(current.memberCount ?? 0) 成员", systemImage: "person.2")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let role = current.role {
                        NWStatusChip(text: role)
                    }
                    if current.isMember == true || current.role != nil {
                        Text("已加入")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.openStatus)
                    }
                }
            }

            if let code = current.inviteCode, !code.isEmpty {
                HStack(spacing: AppTheme.space12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("邀请码")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(code)
                            .font(.body.monospaced().weight(.semibold))
                    }
                    Spacer(minLength: 0)
                    Button("复制") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                        message = "邀请码已复制"
                    }
                    .buttonStyle(.bordered)
                }
                .padding(AppTheme.space16)
                .ninewoodCard()
            }

            if !(current.isMember == true || current.role != nil) {
                Button {
                    Task { await join() }
                } label: {
                    Text(isJoining ? "加入中…" : "加入圈子")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isJoining)
            }
        }
    }

    @ViewBuilder
    private var overviewSection: some View {
        if isLoadingHub && hub == nil && hubError == nil {
            ProgressView().padding(.top, AppTheme.space12)
        } else if let hubError {
            NWEmptyState(title: "概览暂不可用", systemImage: "exclamationmark.triangle", message: hubError)
        } else {
            if let ann = hub?.announcement, let title = ann.title {
                VStack(alignment: .leading, spacing: AppTheme.space8) {
                    Text("公告").font(.headline)
                    Text(title).font(.body.weight(.semibold))
                    if let body = ann.body {
                        Text(body).foregroundStyle(.secondary)
                    }
                }
                .padding(AppTheme.space16)
                .ninewoodCard()
            }

            if let stats = hub?.stats {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 130), spacing: AppTheme.space12)],
                    spacing: AppTheme.space12
                ) {
                    hubStat("成员", "\(stats.memberCount ?? current.memberCount ?? 0)")
                    hubStat("今日活跃", "\(stats.todayActive ?? 0)")
                    hubStat("本周需求", "\(stats.weekDemands ?? 0)")
                    hubStat("资源更新", "\(stats.resourceUpdates ?? 0)")
                }
            } else if hub?.announcement == nil {
                NWEmptyState(title: "暂无 Hub 数据", systemImage: "chart.bar", message: "加入圈子后可查看统计与动态")
            }
        }
    }

    private func hubStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.space12)
        .background(AppTheme.fill.opacity(0.4), in: RoundedRectangle(cornerRadius: AppTheme.buttonRadius, style: .continuous))
    }

    @ViewBuilder
    private var membersSection: some View {
        if let membersError, members.isEmpty {
            NWEmptyState(title: "成员加载失败", systemImage: "person.2", message: membersError)
        } else if members.isEmpty {
            NWEmptyState(title: "暂无成员列表", systemImage: "person.2", message: "加入圈子后可查看成员")
        } else {
            VStack(spacing: 0) {
                ForEach(members) { member in
                    HStack(spacing: AppTheme.space12) {
                        NWAvatarView(
                            url: member.user?.avatarMediaURL,
                            name: member.user?.nickname ?? "用户",
                            size: 36
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.user?.nickname ?? "用户")
                                .font(.body.weight(.semibold))
                            Text(member.lastActiveLabel ?? member.joinedAt ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if let role = member.role {
                            NWStatusChip(text: role)
                        }
                    }
                    .padding(.vertical, 10)
                    if member.id != members.last?.id {
                        Divider()
                    }
                }
            }
            .padding(AppTheme.space16)
            .ninewoodCard()
        }
    }

    @ViewBuilder
    private var resourcesSection: some View {
        if let resourcesError, resources.isEmpty {
            NWEmptyState(title: "资源加载失败", systemImage: "folder", message: resourcesError)
        } else if resources.isEmpty {
            NWEmptyState(title: "暂无资源", systemImage: "folder", message: "圈子资源会出现在这里")
        } else {
            VStack(spacing: 0) {
                ForEach(resources) { item in
                    HStack(spacing: AppTheme.space12) {
                        Image(systemName: "doc")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "文件")
                                .font(.body.weight(.semibold))
                            Text([item.category, item.sizeLabel, item.uploader?.nickname].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if let fileUrl = item.fileUrl, let url = APIConfig.mediaURL(fileUrl) {
                            Link(destination: url) {
                                Image(systemName: "arrow.down.circle")
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    if item.id != resources.last?.id { Divider() }
                }
            }
            .padding(AppTheme.space16)
            .ninewoodCard()
        }
    }

    @ViewBuilder
    private var activitySection: some View {
        if let activitiesError, activities.isEmpty {
            NWEmptyState(title: "动态加载失败", systemImage: "bolt", message: activitiesError)
        } else if activities.isEmpty {
            NWEmptyState(title: "暂无动态", systemImage: "bolt", message: "圈子活动会出现在这里")
        } else {
            VStack(spacing: 0) {
                ForEach(activities) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title ?? item.type ?? "动态")
                            .font(.body.weight(.semibold))
                        if let summary = item.summary {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text([item.actor?.nickname, item.createdAt].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    if item.id != activities.last?.id { Divider() }
                }
            }
            .padding(AppTheme.space16)
            .ninewoodCard()
        }
    }

    @ViewBuilder
    private var analyticsSection: some View {
        if isLoadingAnalytics && analytics == nil && analyticsError == nil {
            ProgressView().padding(.top, AppTheme.space12)
        } else if let analyticsError {
            NWEmptyState(title: "分析暂不可用", systemImage: "chart.line.uptrend.xyaxis", message: analyticsError)
        } else if let analytics {
            VStack(alignment: .leading, spacing: AppTheme.space12) {
                if let rangeLabel = analytics.rangeLabel {
                    Text("统计区间：\(rangeLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let kpis = analytics.kpis {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 130), spacing: AppTheme.space12)],
                        spacing: AppTheme.space12
                    ) {
                        hubStat("成员", "\(kpis.memberCount ?? 0)")
                        hubStat("成员增长", formatPct(kpis.memberGrowthPct))
                        hubStat("活跃率", formatPct(kpis.activeRate))
                        hubStat("本周需求", "\(kpis.weekDemands ?? 0)")
                        hubStat("互动", "\(kpis.interactions ?? 0)")
                    }
                } else {
                    NWEmptyState(title: "暂无 KPI", systemImage: "chart.bar", message: "服务器未返回统计数据")
                }
            }
        } else {
            NWEmptyState(title: "暂无分析数据", systemImage: "chart.bar", message: "切换到本页将加载圈子统计")
        }
    }

    @ViewBuilder
    private var manageSection: some View {
        if !canManage {
            NWEmptyState(
                title: "需要管理员权限",
                systemImage: "lock",
                message: "仅圈主或管理员可发布公告与邀请成员"
            )
        } else {
            VStack(alignment: .leading, spacing: AppTheme.space16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("公告").font(.headline)
                    TextField("标题", text: $annTitle)
                        .textFieldStyle(.roundedBorder)
                    TextEditor(text: $annBody)
                        .frame(minHeight: 80)
                        .padding(AppTheme.space8)
                        .background(AppTheme.fill.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Toggle("置顶公告", isOn: $annPinned)
                    Button {
                        Task { await postAnnouncement() }
                    } label: {
                        Text(isPostingAnn ? "发布中…" : "发布公告")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        isPostingAnn
                            || annTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || annBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
                .padding(AppTheme.space16)
                .ninewoodCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("邮件邀请").font(.headline)
                    TextField("邮箱地址", text: $inviteEmail)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        Task { await sendInvite() }
                    } label: {
                        Text(isInviting ? "发送中…" : "发送邀请")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        isInviting
                            || inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
                .padding(AppTheme.space16)
                .ninewoodCard()

                Button {
                    Task { await sendHeartbeat() }
                } label: {
                    Label(isHeartbeating ? "发送中…" : "圈子心跳", systemImage: "heart")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.bordered)
                .disabled(isHeartbeating)

                if let manageMessage {
                    Text(manageMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func formatPct(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%%", value)
    }

    private func loadAll() async {
        isLoadingHub = true
        hubError = nil
        membersError = nil
        resourcesError = nil
        activitiesError = nil
        analytics = nil
        analyticsError = nil
        defer { isLoadingHub = false }
        do {
            let fetched = try await session.circleService.get(id: circle.id)
            detail = CircleDTO(
                id: fetched.id,
                name: fetched.name,
                description: fetched.description,
                memberCount: fetched.memberCount,
                cityCode: fetched.cityCode,
                isMember: circle.isMember ?? fetched.isMember,
                role: circle.role ?? fetched.role,
                coverUrl: fetched.coverUrl,
                inviteCode: fetched.inviteCode ?? circle.inviteCode,
                type: fetched.type,
                ownerId: fetched.ownerId,
                owner: fetched.owner
            )
        } catch {
            detail = circle
        }
        do {
            hub = try await session.circleService.hubHome(id: circle.id)
        } catch {
            hubError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        do {
            members = try await session.circleService.members(id: circle.id)
        } catch {
            members = []
            membersError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        do {
            resources = try await session.circleService.resources(id: circle.id)
        } catch {
            resources = []
            resourcesError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        do {
            activities = try await session.circleService.activities(id: circle.id)
        } catch {
            activities = []
            activitiesError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadAnalytics() async {
        isLoadingAnalytics = true
        analyticsError = nil
        defer { isLoadingAnalytics = false }
        do {
            analytics = try await session.circleService.analytics(id: circle.id)
        } catch {
            analyticsError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func postAnnouncement() async {
        isPostingAnn = true
        defer { isPostingAnn = false }
        do {
            try await session.circleService.postAnnouncement(
                circleId: circle.id,
                title: annTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                body: annBody.trimmingCharacters(in: .whitespacesAndNewlines),
                pinned: annPinned
            )
            manageMessage = "公告已发布"
            annTitle = ""
            annBody = ""
            annPinned = false
            await loadAll()
        } catch {
            manageMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func sendInvite() async {
        isInviting = true
        defer { isInviting = false }
        do {
            try await session.circleService.createInvite(
                circleId: circle.id,
                email: inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            manageMessage = "邀请已发送"
            inviteEmail = ""
        } catch {
            manageMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func sendHeartbeat() async {
        isHeartbeating = true
        defer { isHeartbeating = false }
        do {
            try await session.circleService.heartbeat(circleId: circle.id)
            manageMessage = "心跳已发送"
        } catch {
            manageMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func join() async {
        isJoining = true
        defer { isJoining = false }
        do {
            try await session.circleService.join(id: circle.id)
            message = "已加入"
            await loadAll()
            onJoined()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct JoinCircleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var code: String
    var onJoin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.space16) {
            Text("邀请码加入")
                .font(.title2.bold())
            Text("输入圈子邀请码，加入后会出现在「我的」列表。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("邀请码", text: $code)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("加入") { onJoin() }
                    .buttonStyle(.borderedProminent)
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(AppTheme.space24)
    }
}

private struct CreateCircleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    var onCreated: (CircleDTO) -> Void
    @State private var name = ""
    @State private var description = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.space16) {
            Text("创建圈子")
                .font(.title2.bold())
            TextField("名称", text: $name)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $description)
                .frame(minHeight: 100)
                .padding(AppTheme.space8)
                .background(AppTheme.fill.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(AppTheme.error)
                    .font(.caption)
            }
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("创建") {
                    Task { await create() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
        .padding(AppTheme.space24)
    }

    private func create() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let created = try await session.circleService.create(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : description.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            onCreated(created)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
