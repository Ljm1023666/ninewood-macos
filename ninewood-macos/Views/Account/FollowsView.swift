import AppKit
import SwiftUI

/// 关注与粉丝（渲染图 23）：设计预览走 fixtures，线上模式走 UserService。
struct FollowsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case following = "关注"
        case followers = "粉丝"
        var id: String { rawValue }
    }

    /// 非 nil 时启用设计 fixtures（忽略传入数组内容，仅作模式开关）。
    private let previewUsers: [SoftUserDTO]?

    @Environment(AppSession.self) private var session
    @State private var tab: Tab = .following
    @State private var keyword = ""
    @State private var selectedID: String
    @State private var isFollowingSelected = true
    @State private var liveFollowing: [SoftUserDTO] = []
    @State private var liveFollowers: [SoftUserDTO] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var followBusy = false
    @State private var followingOverrides: [String: Bool] = [:]
    @State private var actionMessage: String?

    private var usesFixtures: Bool { previewUsers != nil }

    init(previewUsers: [SoftUserDTO]? = nil) {
        self.previewUsers = previewUsers
        _selectedID = State(
            initialValue: previewUsers != nil
                ? FollowsDesignFixtures.following.first!.id
                : ""
        )
    }

    private var source: [FollowsDesignPerson] {
        if usesFixtures {
            return tab == .following ? FollowsDesignFixtures.following : FollowsDesignFixtures.followers
        }
        let users = tab == .following ? liveFollowing : liveFollowers
        return users.map { person(from: $0) }
    }

    private var filtered: [FollowsDesignPerson] {
        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return source }
        return source.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.title.localizedCaseInsensitiveContains(q)
                || $0.tags.joined(separator: " ").localizedCaseInsensitiveContains(q)
        }
    }

    private var selected: FollowsDesignPerson? {
        filtered.first(where: { $0.id == selectedID }) ?? filtered.first
    }

    var body: some View {
        HStack(spacing: 0) {
            listPane
                .paneColumn(minWidth: 300, idealWidth: 340)

            Divider()

            Group {
                if let selected {
                    FollowsProfileDetail(
                        person: selected,
                        isFollowing: $isFollowingSelected,
                        followBusy: followBusy,
                        onMessage: messageAction(for: selected.id),
                        onToggleFollow: toggleFollowAction(for: selected.id),
                        onOpenAllServices: usesFixtures
                            ? nil
                            : { _ = session.navigation.navigate(to: "/service-cards") }
                    )
                    .nwStableDetailIdentity(selected.id)
                } else if isLoading && !usesFixtures {
                    ProgressView("加载中…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError, !usesFixtures, source.isEmpty {
                    NWEmptyState(title: "加载失败", systemImage: "wifi.exclamationmark", message: loadError)
                } else {
                    NWDetailPlaceholder(title: "选择用户", systemImage: "person.2")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("关注")
        .task { await load() }
        .onChange(of: tab) { _, _ in
            selectedID = source.first?.id ?? ""
            keyword = ""
            syncFollowingSelected()
            if !usesFixtures {
                Task { await load() }
            }
        }
        .alert("关注", isPresented: Binding(
            get: { actionMessage != nil },
            set: { if !$0 { actionMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(actionMessage ?? "")
        }
    }

    private func person(from user: SoftUserDTO) -> FollowsDesignPerson {
        FollowsDesignMapper.person(
            from: user,
            isFollowing: isFollowing(user)
        )
    }

    private func isFollowing(_ user: SoftUserDTO) -> Bool {
        followingOverrides[user.id] ?? user.isFollowing ?? (tab == .following)
    }

    private func syncFollowingSelected() {
        guard let selected else {
            isFollowingSelected = tab == .following
            return
        }
        if usesFixtures {
            isFollowingSelected = tab == .following || selected.isFollowing
        } else if let user = (tab == .following ? liveFollowing : liveFollowers).first(where: { $0.id == selected.id }) {
            isFollowingSelected = isFollowing(user)
        } else {
            isFollowingSelected = selected.isFollowing
        }
    }

    private func load() async {
        guard !usesFixtures else { return }
        guard let userId = session.currentUserId else {
            loadError = "请先登录"
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            if tab == .following {
                liveFollowing = try await session.userService.following(id: userId)
            } else {
                liveFollowers = try await session.userService.followers(id: userId)
            }
            if selectedID.isEmpty || !source.contains(where: { $0.id == selectedID }) {
                selectedID = source.first?.id ?? ""
            }
            syncFollowingSelected()
        } catch {
            if tab == .following {
                liveFollowing = []
            } else {
                liveFollowers = []
            }
            selectedID = ""
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func toggleFollow(for userID: String) async {
        guard !followBusy else { return }
        followBusy = true
        defer { followBusy = false }
        do {
            if isFollowingSelected {
                try await session.userService.unfollow(id: userID)
                followingOverrides[userID] = false
                isFollowingSelected = false
                actionMessage = "已取消关注"
            } else {
                try await session.userService.follow(id: userID)
                followingOverrides[userID] = true
                isFollowingSelected = true
                actionMessage = "已关注"
            }
        } catch {
            actionMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func toggleFollowAction(for userID: String) -> (() async -> Void)? {
        guard !usesFixtures else { return nil }
        return { await toggleFollow(for: userID) }
    }

    private func messageAction(for userID: String) -> (() -> Void)? {
        guard !usesFixtures else { return nil }
        return { session.navigation.openDirectMessage(peerID: userID) }
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Tab.allCases) { item in
                    Button {
                        tab = item
                    } label: {
                        Text(item.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tab == item ? .white : AppTheme.secondaryLabel)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(tab == item ? AppTheme.primary : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(AppTheme.fill.opacity(0.7), in: Capsule(style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            NWSearchBar(
                text: $keyword,
                placeholder: tab == .following ? "搜索你关注的专业人士" : "搜索你的粉丝"
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            if isLoading && !usesFixtures && filtered.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                Spacer(minLength: 0)
            } else if let loadError, !usesFixtures, source.isEmpty {
                NWEmptyState(
                    title: "加载失败",
                    systemImage: "wifi.exclamationmark",
                    message: loadError
                )
                Spacer(minLength: 0)
            } else if filtered.isEmpty {
                NWEmptyState(
                    title: tab == .following ? "暂无关注" : "暂无粉丝",
                    systemImage: "person.2",
                    message: keyword.isEmpty ? "这里还没有人" : "换个关键词试试"
                )
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { person in
                            Button {
                                selectedID = person.id
                                syncFollowingSelected()
                            } label: {
                                FollowsListRow(
                                    person: person,
                                    isSelected: person.id == selected?.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 16)
                }
            }
        }
    }
}

// MARK: - List row

private struct FollowsListRow: View {
    let person: FollowsDesignPerson
    var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FollowsAvatar(
                name: person.name,
                asset: person.avatarAsset,
                avatarURL: person.avatarURL,
                size: 46,
                online: person.isOnline
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(person.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.onSurface)
                    if person.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.primary)
                    }
                }

                Text(person.title)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryLabel)

                Text(person.tags.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel.opacity(0.85))
                    .lineLimit(1)

                Text(person.availabilityText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(person.isAvailable ? AppTheme.openStatus : AppTheme.urgent)
            }

            Spacer(minLength: 0)

            if person.hasUpdate {
                Circle()
                    .fill(AppTheme.primary)
                    .frame(width: 7, height: 7)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .nwSelectionChrome(isSelected: isSelected, cornerRadius: 12)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? AppTheme.primary.opacity(0.35) : Color.clear, lineWidth: 1)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Detail

private struct FollowsProfileDetail: View {
    let person: FollowsDesignPerson
    @Binding var isFollowing: Bool
    var followBusy = false
    var onMessage: (() -> Void)?
    var onToggleFollow: (() async -> Void)?
    var onOpenAllServices: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Text(person.bio)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                tagsSection
                statsSection
                if person.mutualCount > 0 {
                    mutualSection
                }
                servicesSection
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .background(AppTheme.workspaceBackground)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            FollowsAvatar(
                name: person.name,
                asset: person.avatarAsset,
                avatarURL: person.avatarURL,
                size: 72,
                online: person.isOnline
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(person.name)
                        .font(.system(size: 22, weight: .bold))
                    if person.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.primary)
                    }
                }
                Text(person.title)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.secondaryLabel)
                Text(person.tags.prefix(3).joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryLabel.opacity(0.9))
                Text(person.availabilityText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(person.isAvailable ? AppTheme.openStatus : AppTheme.urgent)
            }

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                Button {
                    onMessage?()
                } label: {
                    Text("发消息")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    if let onToggleFollow {
                        Task { await onToggleFollow() }
                    } else {
                        isFollowing.toggle()
                    }
                } label: {
                    Text(followBusy ? "…" : (isFollowing ? "取消关注" : "关注"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.onSurface)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        )
                }
                .buttonStyle(.plain)
                .disabled(followBusy)
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("服务领域")
                .font(.system(size: 14, weight: .semibold))
            HStack(spacing: 8) {
                ForEach(person.serviceAreas, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppTheme.surfaceLow, in: Capsule(style: .continuous))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                        }
                }
            }
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("已完成工作 · 隐去信息")
                .font(.system(size: 14, weight: .semibold))
            HStack(spacing: 12) {
                statCard(icon: "shippingbox", title: "项目交付", value: person.deliveryCount)
                statCard(icon: "person.2", title: "长期合作", value: person.longTermCount)
                statCard(icon: "star.fill", title: "客户满意度", value: person.satisfaction)
            }
        }
    }

    private func statCard(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 34, height: 34)
                .background(AppTheme.softPrimary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
                Text(value)
                    .font(.system(size: 15, weight: .bold))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
        }
    }

    private var mutualSection: some View {
        HStack(spacing: 10) {
            HStack(spacing: -8) {
                ForEach(Array(FollowsDesignFixtures.mutualAvatars.enumerated()), id: \.offset) { _, asset in
                    FollowsAvatar(name: "友", asset: asset, size: 28, online: false)
                        .overlay {
                            Circle().stroke(AppTheme.surface, lineWidth: 2)
                        }
                }
            }
            Text("等 \(person.mutualCount) 位你关注的人也关注了他")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondaryLabel)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryLabel)
        }
        .padding(12)
        .background(AppTheme.surfaceLow, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("近期公开服务")
                .font(.system(size: 14, weight: .semibold))
            ForEach(person.services) { service in
                VStack(alignment: .leading, spacing: 8) {
                    Text(service.title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(service.summary)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .lineLimit(2)
                    HStack {
                        Text(service.priceText)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AppTheme.onSurface)
                        Spacer()
                        Text(service.deliveryText)
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                }
            }
            Button {
                onOpenAllServices?()
            } label: {
                HStack(spacing: 4) {
                    Text("查看全部服务")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.primary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .disabled(onOpenAllServices == nil)
            .opacity(onOpenAllServices == nil ? 0.45 : 1)
        }
    }
}

// MARK: - Avatar

private struct FollowsAvatar: View {
    let name: String
    let asset: String?
    var avatarURL: URL?
    let size: CGFloat
    var online: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let asset, NSImage(named: asset) != nil {
                    Image(asset)
                        .resizable()
                        .scaledToFill()
                } else if let avatarURL {
                    NWAvatarView(url: avatarURL, name: name, size: size)
                } else {
                    Circle()
                        .fill(AppTheme.fill.opacity(0.7))
                        .overlay {
                            Text(String(name.prefix(1)))
                                .font(.system(size: size * 0.38, weight: .semibold))
                                .foregroundStyle(AppTheme.primary)
                        }
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(AppTheme.outlineVariant.opacity(0.5), lineWidth: 0.5)
            }

            if online {
                Circle()
                    .fill(AppTheme.openStatus)
                    .frame(width: size * 0.22, height: size * 0.22)
                    .overlay {
                        Circle().stroke(AppTheme.surface, lineWidth: 2)
                    }
                    .offset(x: 1, y: 1)
            }
        }
    }
}

// MARK: - Fixtures

struct FollowsDesignPerson: Identifiable, Hashable {
    let id: String
    let name: String
    let title: String
    let tags: [String]
    let serviceAreas: [String]
    let availabilityText: String
    let isAvailable: Bool
    let isOnline: Bool
    let isVerified: Bool
    let hasUpdate: Bool
    let isFollowing: Bool
    let bio: String
    let deliveryCount: String
    let longTermCount: String
    let satisfaction: String
    let mutualCount: Int
    let avatarAsset: String?
    let avatarURL: URL?
    let services: [FollowsDesignService]
}

private enum FollowsDesignMapper {
    static func person(from user: SoftUserDTO, isFollowing: Bool) -> FollowsDesignPerson {
        let name = user.nickname ?? "用户"
        let cert = user.certificationLevel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isVerified = !cert.isEmpty && cert.uppercased() != "NONE"
        var titleParts: [String] = []
        if !cert.isEmpty, cert.uppercased() != "NONE" {
            titleParts.append(certLabel(cert))
        }
        if let region = user.ipRegion, !region.isEmpty {
            titleParts.append(region)
        }
        let completed = user.completedOrders ?? 0
        return FollowsDesignPerson(
            id: user.id,
            name: name,
            title: titleParts.isEmpty ? "九木用户" : titleParts.joined(separator: " · "),
            tags: [],
            serviceAreas: [],
            availabilityText: completed > 0 ? "已完成 \(completed) 单" : "可沟通合作",
            isAvailable: true,
            isOnline: false,
            isVerified: isVerified,
            hasUpdate: false,
            isFollowing: isFollowing,
            bio: user.bio?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? user.bio!
                : "暂无简介",
            deliveryCount: completed > 0 ? "\(completed)+" : "—",
            longTermCount: "—",
            satisfaction: user.creditScore.map { "信用 \($0)" } ?? "—",
            mutualCount: 0,
            avatarAsset: nil,
            avatarURL: user.avatarMediaURL,
            services: []
        )
    }

    private static func certLabel(_ raw: String) -> String {
        switch raw.uppercased() {
        case "PRO": "PRO"
        case "VERIFIED", "CERTIFIED": "认证服务者"
        default: raw
        }
    }
}

struct FollowsDesignService: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let priceText: String
    let deliveryText: String
}

enum FollowsDesignFixtures {
    static let mutualAvatars = ["AvatarLinXia", "AvatarFangZhou", "AvatarXuYan", "AvatarZhangMo"]

    static let following: [FollowsDesignPerson] = [
        FollowsDesignPerson(
            id: "follow-1",
            name: "陈知远",
            title: "产品策略 · 认证专家",
            tags: ["产品规划", "用户研究", "增长策略"],
            serviceAreas: ["产品规划", "用户研究", "增长策略", "数据分析", "MVP 验证"],
            availabilityText: "有空 · 可接新项目",
            isAvailable: true,
            isOnline: true,
            isVerified: true,
            hasUpdate: true,
            isFollowing: true,
            bio: "专注消费与工具类产品的策略与验证，擅长把模糊目标拆成可验证的机会与路径。近三年以匿名协作完成多轮产品定位、用户研究与增长实验，重视过程透明与可复用交付。",
            deliveryCount: "20+",
            longTermCount: "8+",
            satisfaction: "4.9 / 5.0",
            mutualCount: 12,
            avatarAsset: "AvatarChenShu",
            avatarURL: nil,
            services: [
                FollowsDesignService(id: "s1", title: "产品机会评估", summary: "梳理目标用户与关键场景，输出机会优先级与验证建议。", priceText: "¥3,800 起", deliveryText: "2 周交付"),
                FollowsDesignService(id: "s2", title: "用户研究与洞察报告", summary: "访谈提纲、执行纪要与结构化洞察，支持产品决策。", priceText: "¥4,600 起", deliveryText: "3 周交付"),
                FollowsDesignService(id: "s3", title: "增长实验设计", summary: "围绕激活与留存设计可落地的实验方案与指标。", priceText: "¥2,900 起", deliveryText: "10 天交付")
            ]
        ),
        FollowsDesignPerson(
            id: "follow-2",
            name: "周屿",
            title: "品牌视觉 · PRO",
            tags: ["品牌升级", "图标设计", "多端适配"],
            serviceAreas: ["品牌视觉", "产品图标", "设计规范"],
            availabilityText: "忙碌 · 约 3 天后有空",
            isAvailable: false,
            isOnline: false,
            isVerified: true,
            hasUpdate: false,
            isFollowing: true,
            bio: "产品与品牌视觉设计，重视过程透明与可靠交付。",
            deliveryCount: "46+",
            longTermCount: "12+",
            satisfaction: "4.9 / 5.0",
            mutualCount: 8,
            avatarAsset: "AvatarFangZhou",
            avatarURL: nil,
            services: [
                FollowsDesignService(id: "s1", title: "品牌视觉与产品图标设计", summary: "从风格探索到多端图标交付。", priceText: "¥2,800 起", deliveryText: "2 周交付")
            ]
        ),
        FollowsDesignPerson(
            id: "follow-3",
            name: "程野",
            title: "用户研究 · 认证服务者",
            tags: ["用户访谈", "研究报告", "内容整理"],
            serviceAreas: ["用户访谈", "洞察报告", "内容整理"],
            availabilityText: "有空 · 可接新项目",
            isAvailable: true,
            isOnline: true,
            isVerified: true,
            hasUpdate: true,
            isFollowing: true,
            bio: "用户研究与内容整理，擅长把访谈材料沉淀为可执行洞察。",
            deliveryCount: "31+",
            longTermCount: "6+",
            satisfaction: "4.8 / 5.0",
            mutualCount: 5,
            avatarAsset: "AvatarXuYan",
            avatarURL: nil,
            services: [
                FollowsDesignService(id: "s1", title: "用户访谈与洞察报告", summary: "访谈提纲、执行与结构化洞察。", priceText: "¥2,200 起", deliveryText: "10 天交付")
            ]
        ),
        FollowsDesignPerson(
            id: "follow-4",
            name: "乔安",
            title: "数据分析 · 认证服务者",
            tags: ["数据分析", "研究报告", "指标设计"],
            serviceAreas: ["数据分析", "指标设计", "研究报告"],
            availabilityText: "忙碌 · 本周排期满",
            isAvailable: false,
            isOnline: false,
            isVerified: true,
            hasUpdate: false,
            isFollowing: true,
            bio: "数据分析和研究报告，关注指标口径与可读表达。",
            deliveryCount: "19+",
            longTermCount: "4+",
            satisfaction: "4.7 / 5.0",
            mutualCount: 3,
            avatarAsset: "AvatarZhangMo",
            avatarURL: nil,
            services: [
                FollowsDesignService(id: "s1", title: "产品指标与数据报告", summary: "梳理核心指标并输出可读报告。", priceText: "¥1,800 起", deliveryText: "1 周交付")
            ]
        )
    ]

    static let followers: [FollowsDesignPerson] = [
        FollowsDesignPerson(
            id: "fan-1",
            name: "林夏",
            title: "产品经理 · 需求方",
            tags: ["产品设计", "用户研究"],
            serviceAreas: ["产品规划", "需求梳理"],
            availabilityText: "有空 · 可沟通合作",
            isAvailable: true,
            isOnline: true,
            isVerified: true,
            hasUpdate: false,
            isFollowing: false,
            bio: "长期发布研究与设计类需求，重视过程记录与验收标准。",
            deliveryCount: "—",
            longTermCount: "—",
            satisfaction: "—",
            mutualCount: 4,
            avatarAsset: "AvatarLinXia",
            avatarURL: nil,
            services: []
        ),
        FollowsDesignPerson(
            id: "fan-2",
            name: "方舟",
            title: "内容策略 · 认证服务者",
            tags: ["内容设计", "文档结构"],
            serviceAreas: ["内容设计", "文档优化"],
            availabilityText: "有空 · 可接新项目",
            isAvailable: true,
            isOnline: false,
            isVerified: true,
            hasUpdate: true,
            isFollowing: true,
            bio: "关注文档结构与阅读节奏，服务产品与研究团队。",
            deliveryCount: "14+",
            longTermCount: "3+",
            satisfaction: "4.8 / 5.0",
            mutualCount: 2,
            avatarAsset: "AvatarFangZhou",
            avatarURL: nil,
            services: [
                FollowsDesignService(id: "s1", title: "产品文档结构优化", summary: "让复杂信息更清晰易读。", priceText: "¥900 起", deliveryText: "5 天交付")
            ]
        )
    ]
}
