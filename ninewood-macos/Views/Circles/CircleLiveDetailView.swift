import SwiftUI
import AppKit

/// 06 圈子详情：视觉对齐渲染图，数据与动作全部走真实 API。
struct CircleLiveDetailView: View {
    let circle: CircleDTO
    var onChanged: () -> Void

    @Environment(AppSession.self) private var session

    @State private var tab = "概览"
    @State private var detail: CircleDTO?
    @State private var hub: CircleHubHomeDTO?
    @State private var members: [CircleMemberDTO] = []
    @State private var resources: [CircleResourceDTO] = []
    @State private var activities: [CircleActivityDTO] = []
    @State private var analytics: CircleAnalyticsDTO?
    @State private var isLoading = false
    @State private var message: String?
    @State private var showInviteSheet = false
    @State private var inviteEmail = ""
    @State private var isInviting = false
    @State private var annTitle = ""
    @State private var annBody = ""
    @State private var annPinned = true
    @State private var isPostingAnn = false
    @State private var isResetting = false
    @State private var isLeaving = false
    @State private var isHeartbeating = false
    @State private var memberActionBusyId: String?

    private var current: CircleDTO { detail ?? circle }

    private var visibleTabs: [String] {
        canManage
            ? ["概览", "成员", "资源", "动态", "分析", "管理"]
            : ["概览", "成员", "资源", "动态", "分析"]
    }

    private var canManage: Bool {
        let role = (current.role ?? "").uppercased()
        return role == "OWNER" || role == "ADMIN"
    }

    private var isOwner: Bool {
        (current.role ?? "").uppercased() == "OWNER"
    }

    private var capacity: Int {
        current.memberCapacity ?? hub?.memberCapacity ?? 200
    }

    private var inviteCode: String {
        current.inviteCode ?? "—"
    }

    private var icon: (label: String, color: Color) {
        CirclesDesignPreviewFixtures.iconSpec(for: current)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            Divider()
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    Group {
                        if isLoading && hub == nil && members.isEmpty {
                            ProgressView().padding(.top, 40)
                        } else {
                            switch tab {
                            case "概览": overviewContent
                            case "成员": membersTabContent
                            case "资源": resourcesTabContent
                            case "动态": activityTabContent
                            case "分析": analyticsTabContent
                            default: manageTabContent
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                Divider()
                inspector
                    .frame(width: 214)
            }
        }
        .background(AppTheme.surface)
        .task(id: circle.id) {
            tab = "概览"
            await loadAll()
            try? await session.circleService.heartbeat(circleId: circle.id)
        }
        .onChange(of: tab) { _, newTab in
            if newTab == "分析", analytics == nil {
                Task { await loadAnalytics() }
            }
        }
        .onChange(of: canManage) { _, manage in
            if !manage, tab == "管理" { tab = "概览" }
        }
        .sheet(isPresented: $showInviteSheet) {
            inviteSheet
                .frame(minWidth: 380, minHeight: 220)
        }
        .alert("圈子", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    // MARK: - Header / Tabs

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(icon.color)
                .frame(width: 68, height: 68)
                .overlay {
                    Text(icon.label)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(-1)
                }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(current.name)
                        .font(.title2.bold())
                    if current.type != "PUBLIC" {
                        Image(systemName: "lock.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if let role = current.role {
                        NWStatusChip(text: role)
                    }
                }
                Text(current.description ?? hub?.purpose ?? "暂无简介")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    private var tabBar: some View {
        HStack(spacing: 22) {
            ForEach(visibleTabs, id: \.self) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 8) {
                        Text(item)
                            .font(.subheadline.weight(tab == item ? .semibold : .regular))
                            .foregroundStyle(tab == item ? AppTheme.primary : .secondary)
                        Rectangle()
                            .fill(tab == item ? AppTheme.primary : Color.clear)
                            .frame(height: 2)
                            .frame(maxWidth: 36)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Tabs

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("公告", "megaphone.fill") {
                tab = "管理"
            }
            if let ann = hub?.announcement, let title = ann.title, !title.isEmpty {
                Text(title)
                    .font(.body.weight(.semibold))
                if let body = ann.body {
                    Text(body)
                        .font(.body)
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineSpacing(4)
                        .padding(.top, 4)
                }
                if let created = ann.createdAt {
                    Text(APIDate.relativeOrTime(created))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                }
            } else {
                Text("暂无公告")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            sectionDivider()

            sectionHeader("圈子目的", "target")
            Text(hub?.purpose ?? current.description ?? "暂无简介")
                .font(.body)
                .foregroundStyle(.primary.opacity(0.85))
                .lineSpacing(4)
            sectionDivider()

            sectionHeader("活跃成员", "person.2.fill") {
                tab = "成员"
            }
            activeMembersRow
            sectionDivider()

            sectionHeader("最新资源", "folder.fill") {
                tab = "资源"
            }
            let recent = hub?.recentResources ?? Array(resources.prefix(3))
            if recent.isEmpty {
                Text("暂无资源").font(.subheadline).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(recent) { item in
                        liveResourceRow(item)
                    }
                }
            }
            sectionDivider()

            sectionHeader("最近动态", "bubble.left.and.bubble.right.fill") {
                tab = "动态"
            }
            let recentActs = hub?.activities ?? Array(activities.prefix(5))
            if recentActs.isEmpty {
                Text("暂无动态").font(.subheadline).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 14) {
                    ForEach(recentActs) { item in
                        liveActivityRow(item)
                    }
                }
            }
        }
    }

    private var activeMembersRow: some View {
        let items = hub?.activeMembers?.items ?? []
        let extra = hub?.activeMembers?.extraCount ?? 0
        return HStack(spacing: -8) {
            if items.isEmpty {
                Text("近 7 日暂无活跃成员记录")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items.prefix(8)) { member in
                    NWAvatarView(
                        url: member.avatarMediaURL,
                        name: member.nickname ?? "成员",
                        size: 34
                    )
                    .overlay { Circle().stroke(AppTheme.surface, lineWidth: 2) }
                }
                if extra > 0 {
                    Text("+\(extra)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(AppTheme.surfaceLow, in: Capsule())
                        .padding(.leading, 14)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private var membersTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("成员名册").font(.headline)
                Spacer()
                Text("\(current.memberCount ?? members.count) / \(capacity)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if members.isEmpty {
                NWEmptyState(title: "暂无成员", systemImage: "person.2", message: "加入圈子后可查看成员")
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(members) { member in
                        memberCard(member)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private func memberCard(_ member: CircleMemberDTO) -> some View {
        HStack(spacing: 10) {
            NWAvatarView(
                url: member.user?.avatarMediaURL,
                name: member.user?.nickname ?? "用户",
                size: 36
            )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.user?.nickname ?? "用户")
                        .font(.subheadline.weight(.semibold))
                    if let role = member.role {
                        Text(roleLabel(role))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AppTheme.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.softPrimary, in: Capsule())
                    }
                }
                Text(member.user?.bio ?? member.lastActiveLabel ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if canManageMember(member) {
                Menu {
                    if isOwner, (member.role ?? "").uppercased() == "MEMBER" {
                        Button("设为管理员") {
                            Task { await setRole(member, role: "ADMIN") }
                        }
                    }
                    if isOwner, (member.role ?? "").uppercased() == "ADMIN" {
                        Button("降为成员") {
                            Task { await setRole(member, role: "MEMBER") }
                        }
                    }
                    Button("移出圈子", role: .destructive) {
                        Task { await kick(member) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                }
                .disabled(memberActionBusyId == member.userId)
            }
        }
        .padding(10)
        .ninewoodCard()
    }

    private var resourcesTabContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("圈子资源").font(.headline).padding(.bottom, 8)
            Text("这里沉淀可复用的文档与清单，不是即时聊天记录。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
            if resources.isEmpty {
                NWEmptyState(title: "暂无资源", systemImage: "folder", message: "成员上传后会出现在这里")
            } else {
                ForEach(resources) { item in
                    liveResourceRow(item)
                }
            }
        }
        .padding(.top, 8)
    }

    private var activityTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("圈子动态").font(.headline)
            Text("资源分享、讨论发起与成员加入等 Hub 事件流。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if activities.isEmpty {
                NWEmptyState(title: "暂无动态", systemImage: "bolt", message: "圈子活动会出现在这里")
            } else {
                ForEach(activities) { item in
                    liveActivityRow(item)
                }
            }
        }
        .padding(.top, 8)
    }

    private var analyticsTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("圈子分析").font(.headline)
            if let analytics, let kpis = analytics.kpis {
                if let range = analytics.rangeLabel {
                    Text("统计区间：\(range)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    hubMetric("成员", "\(kpis.memberCount ?? current.memberCount ?? 0)")
                    hubMetric("活跃率", formatPct(kpis.activeRate))
                    hubMetric("本周需求", "\(kpis.weekDemands ?? 0)")
                    hubMetric("互动", "\(kpis.interactions ?? 0)")
                }
            } else if analytics == nil {
                ProgressView().padding(.top, 12)
            } else {
                NWEmptyState(title: "暂无分析数据", systemImage: "chart.bar", message: "服务器未返回 KPI")
            }
        }
        .padding(.top, 8)
    }

    private var manageTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("圈子管理").font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                Text("发布公告").font(.subheadline.weight(.semibold))
                TextField("标题", text: $annTitle)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $annBody)
                    .frame(minHeight: 72)
                    .padding(8)
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
            .padding(14)
            .ninewoodCard()

            VStack(alignment: .leading, spacing: 10) {
                Text("邀请与准入").font(.subheadline.weight(.semibold))
                Text("当前邀请码：\(inviteCode)")
                    .font(.body.monospaced())
                HStack {
                    Button("复制邀请码") { copyInvite() }
                        .buttonStyle(.bordered)
                    Button {
                        Task { await resetInvite() }
                    } label: {
                        Text(isResetting ? "重置中…" : "重置邀请码")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isResetting)
                    Button("邮件邀请") { showInviteSheet = true }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
            .ninewoodCard()

            Button {
                Task { await sendHeartbeat() }
            } label: {
                Label(isHeartbeating ? "发送中…" : "发送圈子心跳", systemImage: "heart")
            }
            .buttonStyle(.bordered)
            .disabled(isHeartbeating)

            if !isOwner {
                Button(role: .destructive) {
                    Task { await leaveCircle() }
                } label: {
                    Text(isLeaving ? "离开中…" : "离开圈子")
                }
                .disabled(isLeaving)
            } else {
                Text("圈主不可直接离开，请先转让管理权。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Inspector

    private var inspector: some View {
        ScrollView {
            VStack(spacing: 12) {
                inviteCard
                ownerCard
                membersCard
                heartbeatCard
                if canManage {
                    Button {
                        showInviteSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            Text("邀请成员")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                if !isOwner {
                    Button {
                        Task { await leaveCircle() }
                    } label: {
                        Text(isLeaving ? "离开中…" : "离开圈子")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.error)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLeaving)
                }
            }
            .padding(14)
        }
        .background(Color(red: 0.975, green: 0.978, blue: 0.982))
    }

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("邀请信息").font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                Text(inviteCode)
                    .font(.body.monospaced().weight(.semibold))
                Spacer(minLength: 0)
                Button(action: copyInvite) {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("复制邀请码")
            }
            Text("仅用于邀请新成员，加入后仍可继续使用直至重置")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if canManage {
                Button {
                    Task { await resetInvite() }
                } label: {
                    Text(isResetting ? "重置中…" : "重置邀请码")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.primary)
                }
                .buttonStyle(.plain)
                .disabled(isResetting)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninewoodCard()
    }

    private var ownerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("圈主").font(.subheadline.weight(.semibold))
            HStack(spacing: 10) {
                NWAvatarView(
                    url: current.owner?.avatarMediaURL,
                    name: current.owner?.nickname ?? "圈主",
                    size: 36
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.owner?.nickname ?? "圈主")
                        .font(.subheadline.weight(.semibold))
                    Text(current.owner?.bio ?? "—")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninewoodCard()
    }

    private var membersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("成员").font(.subheadline.weight(.semibold))
            Text("\(current.memberCount ?? members.count) / \(capacity)")
                .font(.title3.bold())
            let label = hub?.heartbeat?.label ?? "—"
            Text(activityChip(from: label))
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.openStatus)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(AppTheme.openStatus.opacity(0.12), in: Capsule())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninewoodCard()
    }

    private var heartbeatCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("圈子心跳").font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(AppTheme.openStatus)
            }
            Text(hub?.heartbeat?.label ?? "加载中…")
                .font(.subheadline.weight(.medium))
            if let speakers = hub?.heartbeat?.speakers7d {
                Text("近 7 天 \(speakers) 人发言")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninewoodCard()
    }

    private var inviteSheet: some View {
        VStack(alignment: .leading, spacing: AppTheme.space16) {
            Text("邀请成员").font(.title2.bold())
            Text("发送邮件邀请，或把邀请码分享给对方。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("邀请码：\(inviteCode)")
                .font(.body.monospaced().weight(.semibold))
            TextField("邮箱地址", text: $inviteEmail)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("取消") { showInviteSheet = false }
                Spacer()
                Button {
                    Task { await sendInvite() }
                } label: {
                    Text(isInviting ? "发送中…" : "发送邀请")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInviting || inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(AppTheme.space24)
    }

    // MARK: - Rows / helpers

    private func liveResourceRow(_ item: CircleResourceDTO) -> some View {
        HStack(spacing: 12) {
            resourceBadge(for: item)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name ?? "文件")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text([item.uploader?.nickname, APIDate.relativeOrTime(item.createdAt)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if let fileUrl = item.fileUrl, let url = APIConfig.mediaURL(fileUrl) {
                Link(destination: url) {
                    Image(systemName: "arrow.down.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 10)
    }

    private func liveActivityRow(_ item: CircleActivityDTO) -> some View {
        HStack(alignment: .top, spacing: 10) {
            NWAvatarView(
                url: item.actor?.avatarMediaURL,
                name: item.actor?.nickname ?? "成员",
                size: 32
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.actor?.nickname ?? "成员")
                        .font(.subheadline.weight(.semibold))
                    Text(item.title ?? item.type ?? "动态")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(APIDate.relativeOrTime(item.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let summary = item.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func resourceBadge(for item: CircleResourceDTO) -> some View {
        let name = (item.name ?? "").lowercased()
        let mime = (item.mimeType ?? "").lowercased()
        let (label, color): (String, Color) = {
            if name.hasSuffix(".pdf") || mime.contains("pdf") {
                return ("PDF", Color(red: 0.86, green: 0.28, blue: 0.28))
            }
            if name.hasSuffix(".xlsx") || name.hasSuffix(".xls") || mime.contains("sheet") {
                return ("X", Color(red: 0.18, green: 0.62, blue: 0.38))
            }
            return ("W", Color(red: 0.22, green: 0.48, blue: 0.88))
        }()
        return RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(color)
            .frame(width: 34, height: 34)
            .overlay {
                Text(label)
                    .font(.system(size: label == "PDF" ? 9 : 13, weight: .bold))
                    .foregroundStyle(.white)
            }
    }

    private func sectionHeader(_ title: String, _ systemImage: String, seeAll: (() -> Void)? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 22)
            Text(title).font(.headline)
            Spacer()
            if let seeAll {
                Button("查看全部  ›", action: seeAll)
                    .font(.caption)
                    .foregroundStyle(AppTheme.primary)
                    .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 12)
    }

    private func sectionDivider() -> some View {
        Divider().padding(.vertical, 18)
    }

    private func hubMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninewoodCard()
    }

    private func roleLabel(_ role: String) -> String {
        switch role.uppercased() {
        case "OWNER": return "圈主"
        case "ADMIN": return "管理"
        default: return "成员"
        }
    }

    private func activityChip(from heartbeat: String) -> String {
        if heartbeat.contains("很活跃") || heartbeat.contains("活跃") { return "活跃度高" }
        if heartbeat.contains("静") { return "偏静" }
        return heartbeat
    }

    private func formatPct(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%%", value)
    }

    private func canManageMember(_ member: CircleMemberDTO) -> Bool {
        let target = (member.role ?? "").uppercased()
        if target == "OWNER" { return false }
        if isOwner { return true }
        if canManage && target == "MEMBER" { return true }
        return false
    }

    private func copyInvite() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(inviteCode, forType: .string)
        message = "邀请码已复制"
    }

    // MARK: - Networking

    private func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        analytics = nil
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
                owner: fetched.owner,
                memberCapacity: fetched.memberCapacity ?? circle.memberCapacity,
                lastActivity: fetched.lastActivity ?? circle.lastActivity
            )
        } catch {
            detail = circle
        }
        async let hubTask = session.circleService.hubHome(id: circle.id)
        async let membersTask = session.circleService.members(id: circle.id)
        async let resourcesTask = session.circleService.resources(id: circle.id)
        async let activitiesTask = session.circleService.activities(id: circle.id)
        do { hub = try await hubTask } catch { hub = nil }
        do { members = try await membersTask } catch { members = [] }
        do { resources = try await resourcesTask } catch { resources = [] }
        do { activities = try await activitiesTask } catch { activities = [] }
    }

    private func loadAnalytics() async {
        do {
            analytics = try await session.circleService.analytics(id: circle.id)
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func resetInvite() async {
        isResetting = true
        defer { isResetting = false }
        do {
            let code = try await session.circleService.resetInviteCode(circleId: circle.id)
            if var d = detail {
                d = CircleDTO(
                    id: d.id,
                    name: d.name,
                    description: d.description,
                    memberCount: d.memberCount,
                    cityCode: d.cityCode,
                    isMember: d.isMember,
                    role: d.role,
                    coverUrl: d.coverUrl,
                    inviteCode: code,
                    type: d.type,
                    ownerId: d.ownerId,
                    owner: d.owner,
                    memberCapacity: d.memberCapacity,
                    lastActivity: d.lastActivity
                )
                detail = d
            }
            message = "邀请码已重置为 \(code)"
            onChanged()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
            inviteEmail = ""
            showInviteSheet = false
            message = "邀请已发送"
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
            annTitle = ""
            annBody = ""
            message = "公告已发布"
            await loadAll()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func sendHeartbeat() async {
        isHeartbeating = true
        defer { isHeartbeating = false }
        do {
            try await session.circleService.heartbeat(circleId: circle.id)
            message = "心跳已发送"
            await loadAll()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func leaveCircle() async {
        isLeaving = true
        defer { isLeaving = false }
        do {
            try await session.circleService.leave(circleId: circle.id)
            message = "已离开圈子"
            onChanged()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func setRole(_ member: CircleMemberDTO, role: String) async {
        memberActionBusyId = member.userId
        defer { memberActionBusyId = nil }
        do {
            try await session.circleService.updateMemberRole(
                circleId: circle.id,
                userId: member.userId,
                role: role
            )
            message = "角色已更新"
            await loadAll()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func kick(_ member: CircleMemberDTO) async {
        memberActionBusyId = member.userId
        defer { memberActionBusyId = nil }
        do {
            try await session.circleService.removeMember(circleId: circle.id, userId: member.userId)
            message = "已移除成员"
            await loadAll()
            onChanged()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
