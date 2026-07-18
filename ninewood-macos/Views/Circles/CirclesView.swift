import SwiftUI
import AppKit

struct CirclesView: View {
    @Environment(AppSession.self) private var session
    @State private var circles: [CircleDTO] = []
    @State private var selected: CircleDTO?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var joinCode = ""
    @State private var actionMessage: String?
    @State private var showCreate = false
    @State private var showJoinSheet = false
    @State private var searchText = ""
    @State private var listScope = "我加入的私人圈"
    private let previewCircles: [CircleDTO]?

    init(previewCircles: [CircleDTO]? = nil) {
        self.previewCircles = previewCircles
        _circles = State(initialValue: previewCircles ?? [])
        _selected = State(initialValue: previewCircles?.first)
    }

    private var isPreview: Bool { previewCircles != nil }

    private var filteredCircles: [CircleDTO] {
        let scoped: [CircleDTO]
        switch listScope {
        case "我创建的圈子":
            scoped = circles.filter { ($0.role ?? "").uppercased() == "OWNER" }
        default:
            scoped = circles
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return scoped }
        return scoped.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.description ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏始终可见（空态也能「邀请码加入 / 创建」）
            circlesTopBar
            Divider()

            HStack(spacing: 0) {
                listPane
                    .paneColumn(minWidth: 320, idealWidth: 360)

                Divider()

                Group {
                    if let selected {
                        // 圈子 Hub：真机走完整 API；设计预览保留静态稿
                        if isPreview {
                            CircleReferenceDetail(circle: selected)
                                .nwStableDetailIdentity(selected.id)
                        } else {
                            CircleLiveDetailView(circle: selected) {
                                Task { await load() }
                            }
                            .nwStableDetailIdentity(selected.id)
                        }
                    } else {
                        NWDetailPlaceholder(
                            title: "选择圈子",
                            systemImage: "person.3",
                            message: circles.isEmpty
                                ? "先加入或创建一个私人圈"
                                : "从左侧选择一个圈子查看详情"
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppTheme.surfaceLow)
        .navigationTitle("圈子")
        .task { await load() }
        .sheet(isPresented: $showCreate) {
            CreateCircleSheet { created in
                showCreate = false
                selected = created
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

    private var circlesTopBar: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            Button("邀请码加入") { showJoinSheet = true }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.onSurface)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color(red: 0.82, green: 0.84, blue: 0.86), lineWidth: 1)
                }
            Button("创建") { showCreate = true }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Button {
                Task { await load() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color(red: 0.82, green: 0.84, blue: 0.86), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AppTheme.surface)
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            listHeader

            NWSearchBar(text: $searchText, placeholder: "搜索圈子")
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

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
            } else if filteredCircles.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    NWEmptyState(
                        title: circles.isEmpty ? "还没有加入圈子" : "没有匹配的圈子",
                        systemImage: "person.3",
                        message: circles.isEmpty
                            ? "用邀请码加入，或点右上角「创建」新建私人圈。"
                            : "换个关键词试试"
                    )
                    if circles.isEmpty {
                        HStack(spacing: 10) {
                            Button("邀请码加入") { showJoinSheet = true }
                                .buttonStyle(.bordered)
                            Button("创建私人圈") { showCreate = true }
                                .buttonStyle(.borderedProminent)
                                .tint(AppTheme.primary)
                        }
                        .padding(.horizontal, 16)
                    }
                }
                Spacer(minLength: 0)
            } else {
                // 真机与预览共用紧凑列表，对齐 `06-circles` 渲染图
                previewList
            }
        }
        .background(AppTheme.surface)
    }

    private var listHeader: some View {
        Menu {
            Button("我加入的私人圈") { listScope = "我加入的私人圈" }
            Button("我创建的圈子") { listScope = "我创建的圈子" }
        } label: {
            HStack(spacing: 5) {
                Text(listScope)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var previewList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filteredCircles) { circle in
                    Button {
                        selected = circle
                    } label: {
                        CircleCompactRow(circle: circle, isSelected: selected?.id == circle.id, useFixtures: isPreview)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 16)
        }
    }

    private func load() async {
        if let previewCircles, !previewCircles.isEmpty {
            circles = previewCircles
            selected = selected ?? previewCircles.first
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            // Scope Lock：初期只暴露私人圈，不展示公开圈入口
            let remote = try await session.circleService.myCircles()
            circles = remote
            if let selected, remote.contains(where: { $0.id == selected.id }) {
                // keep selection
            } else {
                self.selected = remote.first
            }
        } catch {
            circles = []
            selected = nil
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func joinByCode() async {
        let code = joinCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        do {
            try await session.circleService.joinByCode(code)
            joinCode = ""
            actionMessage = "已加入圈子"
            await load()
        } catch {
            actionMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

enum CirclesDesignPreviewFixtures {
    static let owner = SoftUserDTO(
        id: "preview-ling",
        phone: nil,
        nickname: "Ling",
        avatarUrl: nil,
        coverUrl: nil,
        demandCardCoverUrl: nil,
        creditScore: 96,
        certificationLevel: "PRO",
        completedOrders: 52,
        bio: "产品独立开发者",
        cityCode: nil,
        ipRegion: nil,
        isFollowing: nil,
        serviceTags: nil,
        tags: nil
    )

    static let circles: [CircleDTO] = [
        circle("1", "独立产品人共创组", "独立产品人一起交流、共创、成长。", 128, "OWNER", "9W7X-R2M3", owner),
        circle("2", "增长黑客实战营", "增长实验、渠道复盘与冷启动协作。", 86, "MEMBER", nil, nil),
        circle("3", "AI 应用探索联盟", "AI 产品实践与工具链交流。", 152, "MEMBER", nil, nil),
        circle("4", "UX 设计师互助圈", "设计方法、案例复盘与作品互评。", 64, "MEMBER", nil, nil),
        circle("5", "可持续生活实验室", "可持续生活实践与城市行动。", 73, "MEMBER", nil, nil),
        circle("6", "SaaS 产品增长圈", "SaaS 增长、留存与定价讨论。", 91, "MEMBER", nil, nil),
        circle("7", "内容创作者联盟", "内容选题、分发与变现方法。", 110, "MEMBER", nil, nil),
        circle("8", "独立设计师互助组", "分享工作方法、可靠服务经验与项目复盘。", 18, "MEMBER", nil, AccountDesignPreviewFixtures.users.dropFirst().first)
    ]

    private static func circle(
        _ id: String,
        _ name: String,
        _ description: String,
        _ members: Int,
        _ role: String,
        _ invite: String?,
        _ owner: SoftUserDTO?
    ) -> CircleDTO {
        CircleDTO(
            id: "preview-circle-\(id)",
            name: name,
            description: description,
            memberCount: members,
            cityCode: nil,
            isMember: true,
            role: role,
            coverUrl: nil,
            inviteCode: invite,
            type: "PRIVATE",
            ownerId: owner?.id ?? "preview-owner-\(id)",
            owner: owner
        )
    }

    static func activitySnippet(for circle: CircleDTO) -> String {
        switch circle.id {
        case "preview-circle-1": return "2分钟前  Ling 分享了资源"
        case "preview-circle-2": return "18分钟前  阿岳 发起了讨论"
        case "preview-circle-3": return "1小时前  Mia 更新了资源"
        case "preview-circle-4": return "3小时前  林间 分享了案例"
        case "preview-circle-5": return "昨天  陈曦 发布了活动"
        case "preview-circle-6": return "昨天  王艺 发起了讨论"
        case "preview-circle-7": return "2天前  方舟 分享了资源"
        default: return "3天前  有新成员加入"
        }
    }

    static func iconSpec(for circle: CircleDTO) -> (label: String, color: Color) {
        switch circle.id {
        case "preview-circle-1": return ("独立\n产品", .black)
        case "preview-circle-2": return ("增长\n黑客", Color(red: 0.95, green: 0.55, blue: 0.18))
        case "preview-circle-3": return ("AI", Color(red: 0.48, green: 0.32, blue: 0.85))
        case "preview-circle-4": return ("UX", Color(red: 0.22, green: 0.48, blue: 0.90))
        case "preview-circle-5": return ("可持续", Color(red: 0.18, green: 0.62, blue: 0.42))
        case "preview-circle-6": return ("SaaS", Color(red: 0.12, green: 0.28, blue: 0.55))
        case "preview-circle-7": return ("内容\n创作", Color(red: 0.90, green: 0.62, blue: 0.18))
        default:
            break
        }
        switch circle.name {
        case "独立产品人共创组": return ("独立\n产品", .black)
        case "增长黑客实战营": return ("增长\n黑客", Color(red: 0.95, green: 0.55, blue: 0.18))
        case "AI 应用探索联盟": return ("AI", Color(red: 0.48, green: 0.32, blue: 0.85))
        case "UX 设计师互助圈": return ("UX", Color(red: 0.22, green: 0.48, blue: 0.90))
        case "可持续生活实验室": return ("可持续", Color(red: 0.18, green: 0.62, blue: 0.42))
        case "SaaS 产品增长圈": return ("SaaS", Color(red: 0.12, green: 0.28, blue: 0.55))
        case "内容创作者联盟": return ("内容\n创作", Color(red: 0.90, green: 0.62, blue: 0.18))
        case "独立设计师互助组": return ("设计", Color(red: 0.35, green: 0.38, blue: 0.45))
        default: return (String(circle.name.prefix(2)), Color(red: 0.35, green: 0.38, blue: 0.45))
        }
    }
}

private struct CircleCompactRow: View {
    let circle: CircleDTO
    var isSelected: Bool = false
    var useFixtures: Bool = false

    var body: some View {
        let icon = CirclesDesignPreviewFixtures.iconSpec(for: circle)
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(icon.color)
                .frame(width: 48, height: 48)
                .overlay {
                    Text(icon.label)
                        .font(.system(size: icon.label.count > 3 ? 11 : 13, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(-1)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(circle.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.onSurface)
                    .lineLimit(1)
                Text("\(circle.memberCount ?? 0) 成员")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
                if let snippet = activitySnippet(for: circle) {
                    Text(snippet)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? AppTheme.softPrimary : Color.clear)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(AppTheme.primary)
                    .frame(width: 3)
            }
        }
        .contentShape(Rectangle())
    }

    private func activitySnippet(for circle: CircleDTO) -> String? {
        if let label = circle.lastActivity?.label, !label.isEmpty {
            if let at = circle.lastActivity?.at {
                return "\(APIDate.relativeOrTime(at))  \(label)"
            }
            return label
        }
        if useFixtures {
            return CirclesDesignPreviewFixtures.activitySnippet(for: circle)
        }
        return "—"
    }
}

private struct CircleReferenceDetail: View {
    let circle: CircleDTO
    @State private var tab = "概览"

    private let tabs = ["概览", "成员", "资源", "动态", "分析", "管理"]

    private var icon: (label: String, color: Color) {
        CirclesDesignPreviewFixtures.iconSpec(for: circle)
    }

    private var inviteCode: String {
        circle.inviteCode ?? "9W7X-R2M3"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            Divider()
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    Group {
                        switch tab {
                        case "概览": overviewContent
                        case "成员": membersTabContent
                        case "资源": resourcesTabContent
                        case "动态": activityTabContent
                        case "分析": analyticsTabContent
                        default: manageTabContent
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                Divider()
                inspector
                    .frame(width: 214)
            }
        }
        .background(AppTheme.surface)
    }

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
                    Text(circle.name)
                        .font(.title2.bold())
                    Image(systemName: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(circle.description ?? "暂无简介")
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
            ForEach(tabs, id: \.self) { item in
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

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("公告", "megaphone.fill")
            (
                Text("欢迎新成员！请先阅读")
                    .foregroundStyle(.primary.opacity(0.85))
                + Text("《圈子公约》")
                    .foregroundStyle(AppTheme.primary)
                + Text("，一起保持高质量的交流。")
                    .foregroundStyle(.primary.opacity(0.85))
            )
            .font(.body)
            .lineSpacing(4)
            Text("2026-07-12")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
            sectionDivider()

            sectionHeader("圈子目的", "target")
            Text("连接独立产品人，分享经验与资源，寻找共创伙伴，验证想法，一起把产品做出来。")
                .font(.body)
                .foregroundStyle(.primary.opacity(0.85))
                .lineSpacing(4)
            sectionDivider()

            sectionHeader("活跃成员", "person.2.fill")
            HStack(spacing: -8) {
                ForEach(Array(activeMembers.enumerated()), id: \.offset) { _, member in
                    circleAvatar(name: member.name, asset: member.asset, size: 34)
                        .overlay { Circle().stroke(AppTheme.surface, lineWidth: 2) }
                }
                Text("+120")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(AppTheme.surfaceLow, in: Capsule())
                    .padding(.leading, 14)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
            sectionDivider()

            sectionHeader("最新资源", "folder.fill")
            VStack(spacing: 0) {
                resourceRow(kind: .doc, title: "从 0 到 1：独立产品冷启动清单（2024）", author: "Ling", time: "2 分钟前")
                resourceRow(kind: .sheet, title: "产品定价策略思考框架", author: "阿岳", time: "1 小时前")
                resourceRow(kind: .pdf, title: "独立开发者工具清单 v3.0", author: "Mia", time: "3 小时前")
            }
            sectionDivider()

            sectionHeader("最近动态", "bubble.left.and.bubble.right.fill")
            VStack(spacing: 14) {
                activityRow(name: "Ling", asset: "AvatarChenShu", action: "分享了资源", time: "2 分钟前", comments: nil)
                activityRow(name: "阿岳", asset: "AvatarFangZhou", action: "发起了讨论", time: "1 小时前", comments: 23)
                activityRow(name: "Mia", asset: "AvatarLinXia", action: "分享了资源", time: "3 小时前", comments: nil)
            }
        }
    }

    /// 圈子 Hub 的「成员」——名册与角色，不是群聊会话。
    private var membersTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("成员名册")
                    .font(.headline)
                Spacer()
                Text("\(circle.memberCount ?? 128) / 200")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(Array(roster.enumerated()), id: \.offset) { _, person in
                    HStack(spacing: 10) {
                        circleAvatar(name: person.name, asset: person.asset, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(person.name)
                                    .font(.subheadline.weight(.semibold))
                                if let role = person.role {
                                    Text(role)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(AppTheme.primary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(AppTheme.softPrimary, in: Capsule())
                                }
                            }
                            Text(person.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .ninewoodCard()
                }
            }
        }
        .padding(.top, 8)
    }

    private var resourcesTabContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("圈子资源")
                .font(.headline)
                .padding(.bottom, 8)
            Text("这里沉淀可复用的文档与清单，不是即时聊天记录。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
            resourceRow(kind: .doc, title: "从 0 到 1：独立产品冷启动清单（2024）", author: "Ling", time: "2 分钟前")
            resourceRow(kind: .sheet, title: "产品定价策略思考框架", author: "阿岳", time: "1 小时前")
            resourceRow(kind: .pdf, title: "独立开发者工具清单 v3.0", author: "Mia", time: "3 小时前")
            resourceRow(kind: .doc, title: "共创协作约定（更新版）", author: "Ling", time: "昨天")
            resourceRow(kind: .pdf, title: "访谈提纲模板", author: "陈曦", time: "3 天前")
        }
        .padding(.top, 8)
    }

    private var activityTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("圈子动态")
                .font(.headline)
            Text("资源分享、讨论发起与成员加入等 Hub 事件流。")
                .font(.caption)
                .foregroundStyle(.secondary)
            activityRow(name: "Ling", asset: "AvatarChenShu", action: "分享了资源", time: "2 分钟前", comments: nil)
            activityRow(name: "阿岳", asset: "AvatarFangZhou", action: "发起了讨论", time: "1 小时前", comments: 23)
            activityRow(name: "Mia", asset: "AvatarLinXia", action: "分享了资源", time: "3 小时前", comments: nil)
            activityRow(name: "林间", asset: "AvatarXuYan", action: "加入了圈子", time: "昨天", comments: nil)
            activityRow(name: "方舟", asset: "AvatarFangZhou", action: "更新了公约", time: "2 天前", comments: 5)
        }
        .padding(.top, 8)
    }

    private var analyticsTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("圈子分析")
                .font(.headline)
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                hubMetric("成员", "\(circle.memberCount ?? 128)")
                hubMetric("近 7 日发言", "86")
                hubMetric("本周资源", "12")
                hubMetric("本周讨论", "9")
            }
        }
        .padding(.top, 8)
    }

    private var manageTabContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("圈子管理")
                .font(.headline)
            manageRow("圈子资料", "名称、简介与封面")
            manageRow("邀请与准入", "邀请码、审核与上限")
            manageRow("角色权限", "圈主、管理员与成员")
            manageRow("内容规范", "公约与违规处理")
        }
        .padding(.top, 8)
    }

    private var roster: [(name: String, asset: String?, role: String?, title: String)] {
        [
            ("Ling", "AvatarChenShu", "圈主", "产品独立开发者"),
            ("阿岳", "AvatarFangZhou", "管理", "增长与实验"),
            ("Mia", "AvatarLinXia", nil, "用户研究"),
            ("林间", "AvatarXuYan", nil, "内容策略"),
            ("陈曦", "AvatarZhangMo", nil, "产品设计"),
            ("方舟", "AvatarFangZhou", nil, "品牌视觉")
        ]
    }

    private func hubMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninewoodCard()
    }

    private func manageRow(_ title: String, _ detail: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .ninewoodCard()
    }

    private var activeMembers: [(name: String, asset: String?)] {
        [
            ("Ling", "AvatarChenShu"),
            ("阿岳", "AvatarFangZhou"),
            ("Mia", "AvatarLinXia"),
            ("林间", "AvatarXuYan"),
            ("陈曦", "AvatarZhangMo"),
            ("王艺", nil),
            ("方舟", "AvatarFangZhou"),
            ("许言", "AvatarXuYan"),
            ("张默", "AvatarZhangMo"),
            ("周屿", nil)
        ]
    }

    private func sectionHeader(_ title: String, _ systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 22)
            Text(title)
                .font(.headline)
            Spacer()
            Text("查看全部  ›")
                .font(.caption)
                .foregroundStyle(AppTheme.primary)
        }
        .padding(.bottom, 12)
    }

    private func sectionDivider() -> some View {
        Divider()
            .padding(.vertical, 18)
    }

    private enum ResourceKind { case doc, sheet, pdf }

    private func resourceRow(kind: ResourceKind, title: String, author: String, time: String) -> some View {
        HStack(spacing: 12) {
            resourceBadge(kind)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text("\(author) · \(time)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.down.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }

    private func resourceBadge(_ kind: ResourceKind) -> some View {
        let (label, color): (String, Color) = switch kind {
        case .doc: ("W", Color(red: 0.22, green: 0.48, blue: 0.88))
        case .sheet: ("X", Color(red: 0.18, green: 0.62, blue: 0.38))
        case .pdf: ("PDF", Color(red: 0.86, green: 0.28, blue: 0.28))
        }
        return RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(color)
            .frame(width: 34, height: 34)
            .overlay {
                Text(label)
                    .font(.system(size: kind == .pdf ? 9 : 13, weight: .bold))
                    .foregroundStyle(.white)
            }
    }

    private func activityRow(name: String, asset: String?, action: String, time: String, comments: Int?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            circleAvatar(name: name, asset: asset, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name).font(.subheadline.weight(.semibold))
                    Text(action).font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(time).font(.caption2).foregroundStyle(.tertiary)
                }
                if let comments {
                    Label("\(comments)", systemImage: "bubble.left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var inspector: some View {
        ScrollView {
            VStack(spacing: 12) {
                inviteCard
                ownerCard
                membersCard
                heartbeatCard
                Button {
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
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(inviteCode, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("复制邀请码")
            }
            Text("仅用于邀请新成员，单次有效")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Button("重置邀请码") {}
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.primary)
                .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninewoodCard()
    }

    private var ownerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("圈主").font(.subheadline.weight(.semibold))
            HStack(spacing: 10) {
                circleAvatar(name: circle.owner?.nickname ?? "Ling", asset: "AvatarChenShu", size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(circle.owner?.nickname ?? "Ling")
                        .font(.subheadline.weight(.semibold))
                    Text(circle.owner?.bio ?? "产品独立开发者")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninewoodCard()
    }

    private var membersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("成员").font(.subheadline.weight(.semibold))
            Text("\(circle.memberCount ?? 128) / 200")
                .font(.title3.bold())
            Text("活跃度高")
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
            Text("健康 · 很活跃")
                .font(.subheadline.weight(.medium))
            Text("近 7 天 86 人发言")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninewoodCard()
    }

    @ViewBuilder
    private func circleAvatar(name: String, asset: String?, size: CGFloat) -> some View {
        if let asset, NSImage(named: asset) != nil {
            Image(asset)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            NWAvatarView(url: nil, name: name, size: size)
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
    private let isPreview: Bool

    init(circle: CircleDTO, preview: Bool = false, onJoined: @escaping () -> Void) {
        self.circle = circle
        self.isPreview = preview
        self.onJoined = onJoined
        _detail = State(initialValue: preview ? circle : nil)
        _hub = State(initialValue: preview ? CircleHubHomeDTO(
            stats: CircleHubStatsDTO(todayActive: 9, newDemands: 3, weekDemands: 12, resourceUpdates: 5, memberCount: circle.memberCount, pendingInvites: 2),
            announcement: CircleAnnouncementDTO(title: "本周协作安排", body: "周三晚进行访谈复盘，周五前更新共享研究模板。", pinned: true, createdAt: "2026-07-18T10:00:00Z")
        ) : nil)
    }

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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.workspaceBackground)
        .task(id: circle.id) {
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
        if isPreview {
            detail = circle
            return
        }
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
