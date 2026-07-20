import SwiftUI

struct ProfileView: View {
    @Environment(AppSession.self) private var session
    @State private var selection: ProfileNav = .overview
    @AppStorage("profile.navSidebarExpanded") private var isNavExpanded = true
    @State private var isBusy = false
    @State private var isUpdatingBusy = false
    @State private var walletSummary: WalletSummaryDTO?
    @State private var inProgressOrderCount: Int?
    @State private var loopRunCount: Int?
    private let previewOrders: [Order]?
    private let initialPath: String?

    init(initialPath: String? = nil, previewOrders: [Order]? = nil) {
        self.initialPath = initialPath
        self.previewOrders = previewOrders
        _selection = State(initialValue: ProfileNav.destination(for: initialPath))
    }

    private enum ProfileNav: String, Identifiable, Hashable, CaseIterable {
        case overview
        case wallet, orders, myDemands, myBids
        case serviceCards, cert, providers
        case follows, favorites, notifications, loops, welfare
        case agent, settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: "概览"
            case .wallet: "钱包与托管"
            case .orders: "订单"
            case .myDemands: "我的需求"
            case .myBids: "我的应标"
            case .serviceCards: "服务卡"
            case .cert: "认证中心"
            case .providers: "认证检索"
            case .follows: "关注"
            case .favorites: "收藏"
            case .notifications: "通知"
            case .loops: "我的回"
            case .welfare: "福利中心"
            case .agent: "九木助手"
            case .settings: "设置"
            }
        }

        var systemImage: String {
            switch self {
            case .overview: "person.crop.circle"
            case .wallet: "wallet.pass"
            case .orders: "list.clipboard"
            case .myDemands: "face.smiling"
            case .myBids: "safari"
            case .serviceCards: "rectangle.portrait"
            case .cert: "checkmark.shield"
            case .providers: "magnifyingglass"
            case .follows: "person"
            case .favorites: "star"
            case .notifications: "bell"
            case .loops: "ellipsis.bubble"
            case .welfare: "gift"
            case .agent: "person.crop.circle"
            case .settings: "gearshape"
            }
        }

        static func destination(for path: String?) -> Self {
            guard let path else { return .overview }
            if path.hasPrefix("/orders/") { return .orders }
            if path.hasPrefix("/demands/") { return .myDemands }
            switch path {
            case "/profile", "/": return .overview
            case "/transactions": return .wallet
            case "/orders": return .orders
            case "/my-demands": return .myDemands
            case "/my-bids": return .myBids
            case "/service-cards": return .serviceCards
            case "/cert-center": return .cert
            case "/loops": return .loops
            case "/notifications": return .notifications
            case "/welfare": return .welfare
            case "/agent": return .agent
            case "/settings": return .settings
            case "/follows": return .follows
            case "/favorites": return .favorites
            case "/providers": return .providers
            default: return .overview
            }
        }
    }

    private var isDesignPreview: Bool {
        let env = ProcessInfo.processInfo.environment["NINEWOOD_DESIGN_PREVIEW"]
        return env == "12-profile"
            || env == "12"
            || env == "profile"
            || CommandLine.arguments.contains("--profile-design-preview")
            || CommandLine.arguments.contains("--12-profile-design-preview")
            || previewOrders != nil
    }

    private var overviewIdentity: (name: String, creditScore: Int, certLevel: String) {
        if isDesignPreview {
            return (
                name: ProfileDesignPreviewFixtures.displayName,
                creditScore: ProfileDesignPreviewFixtures.creditScore,
                certLevel: ProfileDesignPreviewFixtures.certLevel
            )
        }
        return (
            name: session.currentUser?.nickname ?? "九木用户",
            creditScore: session.currentUser?.creditScore ?? 60,
            certLevel: session.currentUser?.certificationLevel ?? "未认证"
        )
    }

    private func overviewAvatar(size: CGFloat) -> some View {
        Group {
            if isDesignPreview, NSImage(named: "AvatarLinXia") != nil {
                Image("AvatarLinXia")
                    .resizable()
                    .scaledToFill()
            } else {
                NWAvatarView(
                    url: session.currentUser?.avatarMediaURL,
                    name: overviewIdentity.name,
                    size: size
                )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private func seedDesignPreviewOverview() {
        isBusy = false
        walletSummary = WalletDesignPreviewFixtures.summary
    }

    var body: some View {
        HStack(spacing: 0) {
            NWCollapsibleSidebar(
                isExpanded: isNavExpanded,
                expandedWidth: isDesignPreview ? 174 : 240,
                collapsedWidth: 52
            ) {
                navPane
            } collapsed: {
                collapsedNavRail
            }

            destination(selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transaction { $0.animation = nil }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !isNavExpanded {
                        collapsedContextBar
                    }
                }
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("我的")
        .onAppear {
            applyNavigation(initialPath ?? session.navigation.currentPath)
            if isDesignPreview {
                isNavExpanded = true
                seedDesignPreviewOverview()
            }
        }
        .onChange(of: initialPath) { _, newPath in
            guard let newPath else { return }
            let dest = ProfileNav.destination(for: newPath)
            guard dest != selection else { return }
            // 不重挂载整页，只切二级选中，避免侧栏抖动
            selection = dest
        }
        .onChange(of: session.navigation.request) { _, request in
            guard let request else { return }
            applyNavigation(request.path)
        }
        .task(id: selection) {
            guard selection == .overview, !isDesignPreview else { return }
            await loadOverview()
        }
    }

    private var collapsedContextBar: some View {
        HStack(spacing: 10) {
            Label(selection.title, systemImage: selection.systemImage)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.surface.opacity(0.92))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var collapsedNavRail: some View {
        VStack(spacing: 8) {
            NWPanelToggleButton(role: .profileMenu, isExpanded: false) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isNavExpanded = true
                }
            }
            ForEach([ProfileNav.orders, .myDemands, .settings]) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = item
                    }
                } label: {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(selection == item ? AppTheme.primary : .secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selection == item ? AppTheme.softPrimary : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(item.title)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.workspaceBackground)
    }

    /// 不用 List：嵌套在 NavigationSplitView detail 里时 macOS List 行经常吞点击。
    private var navPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if !isDesignPreview {
                    HStack {
                        Spacer(minLength: 0)
                        NWPanelToggleButton(role: .profileMenu, isExpanded: true) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isNavExpanded = false
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)

                    profileHeaderButton
                        .padding(.bottom, 6)
                }

                navSection("交易", [.orders, .myDemands, .myBids, .wallet])
                // 认证中心 / 自然回在主侧栏一级入口，避免「我的」重复
                navSection("服务", [.serviceCards, .providers])
                navSection("社交", [.follows, .favorites, .notifications, .welfare])
                // 九木助手已提升为主侧栏置顶入口，不再嵌在「我的」
                navSection("其他", [.settings])
            }
            .padding(.horizontal, isDesignPreview ? 8 : 10)
            .padding(.vertical, isDesignPreview ? 14 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppTheme.workspaceBackground)
    }

    private var profileHeaderButton: some View {
        let identity = overviewIdentity
        let selected = selection == .overview

        return Button {
            selection = .overview
        } label: {
            HStack(spacing: 10) {
                overviewAvatar(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(identity.name)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        if isDesignPreview {
                            NWStatusChip(text: identity.certLevel, tint: AppTheme.openStatus)
                        }
                    }
                    Text("信用 \(identity.creditScore)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? AppTheme.softPrimary : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func navSection(_ title: String, _ items: [ProfileNav]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, isDesignPreview ? 12 : 10)
                .padding(.bottom, 4)

            ForEach(items) { item in
                navButton(item)
            }
        }
    }

    private func navButton(_ item: ProfileNav) -> some View {
        let selected = selection == item
        let showDot = item == .notifications && (isDesignPreview || session.unreadMessageCount > 0)
        return Button {
            selection = item
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 18, alignment: .center)
                Text(item.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if showDot {
                    Circle()
                        .fill(AppTheme.primary)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, isDesignPreview ? 7 : 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? AppTheme.softPrimary : Color.clear)
            )
            .foregroundStyle(selected ? AppTheme.primary : .primary)
        }
        .buttonStyle(.plain)
    }

    private var overviewPane: some View {
        let identity = overviewIdentity
        let bio = isDesignPreview
            ? ProfileDesignPreviewFixtures.bio
            : "让可靠回应沉淀为长期协作。"

        return ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.space24) {
                HStack(alignment: .top, spacing: AppTheme.space24) {
                    overviewAvatar(size: 112)

                    VStack(alignment: .leading, spacing: AppTheme.space12) {
                        HStack(spacing: AppTheme.space8) {
                            Text(identity.name)
                                .font(.system(size: 28, weight: .bold))
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(AppTheme.primary)
                            NWStatusChip(text: identity.certLevel, tint: AppTheme.openStatus)
                        }

                        Text(bio)
                            .font(.body)
                            .foregroundStyle(.secondary)

                        if isDesignPreview {
                            Text(ProfileDesignPreviewFixtures.joinDate)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack(spacing: AppTheme.space8) {
                                NWStatusChip(text: "已认证 \(identity.certLevel)", tint: AppTheme.openStatus)
                                NWStatusChip(text: "信用分 \(identity.creditScore)", tint: AppTheme.primary)
                            }
                        } else {
                            HStack(spacing: AppTheme.space12) {
                                Label("信用分 \(identity.creditScore)", systemImage: "heart")
                                Label("已完成 \(session.currentUser?.completedOrders ?? 0)", systemImage: "checkmark.shield")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)

                    Toggle("忙碌中", isOn: Binding(
                        get: { isBusy },
                        set: { value in
                            isBusy = value
                            Task { await updateBusy(value) }
                        }
                    ))
                    .toggleStyle(.switch)
                    .disabled(isUpdatingBusy)
                }

                summaryPanel
                recentActivityPanel
                quickActionsPanel
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.documentBackground)
    }

    private var summaryPanel: some View {
        HStack(spacing: 0) {
            overviewMetric(
                title: "进行中订单",
                value: isDesignPreview
                    ? "\(ProfileDesignPreviewFixtures.inProgressOrders)"
                    : (inProgressOrderCount.map(String.init) ?? "…"),
                caption: "查看订单",
                systemImage: "bag",
                tint: AppTheme.primary,
                destination: .orders
            )
            Divider().padding(.vertical, AppTheme.space16)
            overviewMetric(
                title: "托管余额",
                value: isDesignPreview
                    ? ProfileDesignPreviewFixtures.escrowBalanceText
                    : (walletSummary?.held.value ?? 0).pointsText,
                caption: "查看钱包",
                systemImage: "checkmark.shield",
                tint: AppTheme.openStatus,
                destination: .wallet
            )
            Divider().padding(.vertical, AppTheme.space16)
            overviewMetric(
                title: isDesignPreview ? "未读通知" : "未读消息",
                value: isDesignPreview
                    ? "\(ProfileDesignPreviewFixtures.unreadNotifications)"
                    : "\(session.unreadMessageCount)",
                caption: isDesignPreview ? "查看通知" : "查看消息",
                systemImage: isDesignPreview ? "bell" : "bubble.left.and.bubble.right",
                tint: AppTheme.primary,
                destination: isDesignPreview ? .notifications : nil,
                externalPath: isDesignPreview ? nil : "/messages"
            )
            Divider().padding(.vertical, AppTheme.space16)
            overviewMetric(
                title: "Natural Loop",
                value: isDesignPreview
                    ? "\(ProfileDesignPreviewFixtures.loopRuns) 次"
                    : (loopRunCount.map { "\($0) 次" } ?? "…"),
                caption: "查看记录",
                systemImage: "arrow.triangle.2.circlepath",
                tint: AppTheme.openStatus,
                destination: nil,
                externalPath: "/loops/discover"
            )
        }
        .overviewPanel()
    }

    private func overviewMetric(
        title: String,
        value: String,
        caption: String,
        systemImage: String,
        tint: Color,
        destination: ProfileNav? = nil,
        externalPath: String? = nil
    ) -> some View {
        Button {
            if let externalPath {
                _ = session.navigation.navigate(to: externalPath)
            } else if let destination {
                selection = destination
            }
        } label: {
            VStack(alignment: .leading, spacing: AppTheme.space12) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(AppTheme.space16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var recentActivityPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("近期活动")
                .font(.headline)
                .padding(AppTheme.space16)

            if isDesignPreview {
                ForEach(Array(ProfileDesignPreviewFixtures.activities.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Divider().padding(.leading, 58)
                    }
                    overviewActivity(
                        item.title,
                        detail: item.detail,
                        time: item.time,
                        systemImage: item.symbol,
                        tint: item.tint,
                        destination: item.nav == "loops" ? nil : profileNav(for: item.nav),
                        externalPath: item.nav == "loops" ? "/loops/discover" : nil
                    )
                }
            } else {
                overviewActivity(
                    "查看订单进度",
                    detail: "预付、履约、验收与结算",
                    time: nil,
                    systemImage: "bag",
                    tint: AppTheme.primary,
                    destination: .orders
                )
                Divider().padding(.leading, 58)
                overviewActivity(
                    "检查 Natural Loop",
                    detail: "侧栏「自然回」· 运行记录与资源回路",
                    time: nil,
                    systemImage: "arrow.triangle.2.circlepath",
                    tint: AppTheme.openStatus,
                    externalPath: "/loops/discover"
                )
                Divider().padding(.leading, 58)
                overviewActivity(
                    "管理钱包与托管",
                    detail: "余额、托管与收支明细",
                    time: nil,
                    systemImage: "wallet.pass",
                    tint: AppTheme.openStatus,
                    destination: .wallet
                )
                Divider().padding(.leading, 58)
                overviewActivity(
                    "查看通知",
                    detail: "系统消息与业务对象跳转",
                    time: nil,
                    systemImage: "bell",
                    tint: AppTheme.primary,
                    destination: .notifications
                )
            }
        }
        .overviewPanel()
    }

    private func overviewActivity(
        _ title: String,
        detail: String,
        time: String?,
        systemImage: String,
        tint: Color,
        destination: ProfileNav? = nil,
        externalPath: String? = nil
    ) -> some View {
        Button {
            if let externalPath {
                _ = session.navigation.navigate(to: externalPath)
            } else if let destination {
                selection = destination
            }
        } label: {
            HStack(spacing: AppTheme.space16) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.medium))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let time {
                    Text(time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, AppTheme.space16)
            .padding(.vertical, AppTheme.space12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var quickActionsPanel: some View {
        VStack(alignment: .leading, spacing: AppTheme.space12) {
            Text("快捷操作")
                .font(.headline)

            HStack(spacing: AppTheme.space16) {
                quickAction(
                    "编辑资料",
                    detail: "更新头像、昵称与个人简介",
                    systemImage: "person",
                    destination: .settings
                )
                quickAction(
                    "查看钱包",
                    detail: "管理余额、银行卡与收支明细",
                    systemImage: "wallet.pass",
                    destination: .wallet
                )
            }
        }
        .padding(AppTheme.space16)
        .overviewPanel()
    }

    private func quickAction(
        _ title: String,
        detail: String,
        systemImage: String,
        destination: ProfileNav
    ) -> some View {
        Button {
            selection = destination
        } label: {
            HStack(spacing: AppTheme.space16) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(AppTheme.primary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(AppTheme.space16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(AppTheme.surfaceLow, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func profileNav(for key: String) -> ProfileNav {
        switch key {
        case "wallet": .wallet
        case "loops": .loops
        case "notifications": .notifications
        default: .orders
        }
    }

    private func loadOverview() async {
        async let busyResult = try? session.userService.busyStatus()
        async let walletResult = try? session.walletService.summary()
        async let ordersResult = try? session.orderService.list(page: 1)
        async let loopsResult = try? session.loopService.myRuns(limit: 1)
        let (busy, wallet, orders, loops) = await (busyResult, walletResult, ordersResult, loopsResult)
        if let busy {
            isBusy = busy.isBusy == true
        }
        walletSummary = wallet
        if let orders {
            inProgressOrderCount = orders.filter {
                $0.stage == .accepted || $0.stage == .inProgress || $0.stage == .waitingReview
            }.count
        }
        if let loops {
            loopRunCount = loops.summary?.total ?? loops.items.count
        }
    }

    private func updateBusy(_ value: Bool) async {
        isUpdatingBusy = true
        defer { isUpdatingBusy = false }
        do {
            try await session.userService.updateBusy(isBusy: value)
        } catch {
            isBusy.toggle()
        }
    }

    @ViewBuilder
    private func destination(_ item: ProfileNav) -> some View {
        let useFixtures = previewOrders != nil
        switch item {
        case .overview:
            overviewPane
        case .wallet:
            WalletView(
                previewSummary: useFixtures ? WalletDesignPreviewFixtures.summary : nil,
                previewTransactions: useFixtures ? WalletDesignPreviewFixtures.transactions : nil
            )
        case .orders:
            OrdersListView(
                repository: session.orderRepository,
                previewOrders: previewOrders,
                previewCurrentUserID: useFixtures ? OrdersDesignPreviewFixtures.currentUserID : nil
            )
        case .loops:
            LoopHubView(frontendPreview: useFixtures)
                .accessibilityIdentifier("loop-workspace-hub")
        case .cert:
            CertCenterView(preview: useFixtures)
        case .myDemands:
            MyDemandsView(
                previewDemands: useFixtures ? DesignPreviewFixtures.demands : nil,
                previewApplicants: useFixtures ? DemandManagementPreviewFixtures.applicants : []
            )
        case .myBids:
            MyBidsView(previewItems: useFixtures ? Array(DesignPreviewFixtures.demands.prefix(4)) : nil)
        case .serviceCards:
            ServiceCardsManageView(previewCards: useFixtures ? ServiceCardsDesignPreviewFixtures.cards : nil)
        case .follows:
            FollowsView(previewUsers: useFixtures ? AccountDesignPreviewFixtures.users : nil)
        case .favorites:
            FavoritesView(previewDemands: useFixtures ? Array(DesignPreviewFixtures.demands.prefix(5)) : nil)
        case .notifications:
            NotificationsView(previewItems: useFixtures ? AccountDesignPreviewFixtures.notifications : nil)
        case .providers:
            ProvidersSearchView()
        case .welfare:
            WelfareCenterView(previewItems: useFixtures ? WelfareDesignPreviewFixtures.items : nil)
        case .agent:
            AgentChatView(previewDetails: useFixtures ? AgentDesignPreviewFixtures.details : nil)
        case .settings:
            SettingsView()
        }
    }

    private func applyNavigation(_ path: String) {
        // 认证 / 自然回 / 助手以主侧栏为准，避免「我的」内嵌重复页
        if path == "/cert-center"
            || path == "/loops"
            || path.hasPrefix("/loops/")
            || path == "/agent"
            || path.hasPrefix("/agent/")
        {
            _ = session.navigation.navigate(to: path)
            selection = .overview
            return
        }
        selection = ProfileNav.destination(for: path)
    }
}

enum ProfileDesignPreviewFixtures {
    static let displayName = "林间有风"
    static let certLevel = "L3"
    static let bio = "自然循环践行者，专注可持续解决方案与开源协作。"
    static let joinDate = "加入九木 2023年6月"
    static let creditScore = 86
    static let inProgressOrders = 2
    static let escrowBalanceText = "¥ 18,640.00"
    static let unreadNotifications = 3
    static let loopRuns = 5

    struct ActivityItem {
        let title: String
        let detail: String
        let time: String
        let symbol: String
        let tint: Color
        let nav: String
    }

    static let activities: [ActivityItem] = [
        ActivityItem(
            title: "订单 #2024-0601 任务已更新",
            detail: "生态影像素材拍摄 · 需求方：绿野自然保护中心",
            time: "2 小时前",
            symbol: "bag",
            tint: AppTheme.primary,
            nav: "orders"
        ),
        ActivityItem(
            title: "Natural Loop 运行完成",
            detail: "碳足迹盘点流程 · 运行 ID: NL-240527-0821",
            time: "昨天 18:32",
            symbol: "arrow.triangle.2.circlepath",
            tint: AppTheme.openStatus,
            nav: "loops"
        ),
        ActivityItem(
            title: "托管收款已入账",
            detail: "订单 #2024-0598 · ¥6,800.00",
            time: "昨天 11:06",
            symbol: "wallet.pass",
            tint: AppTheme.openStatus,
            nav: "wallet"
        ),
        ActivityItem(
            title: "您收到一条新消息",
            detail: "来自 自然之友小林",
            time: "5 月 26 日 21:15",
            symbol: "bell",
            tint: AppTheme.primary,
            nav: "notifications"
        )
    ]
}

private extension View {
    func overviewPanel() -> some View {
        self
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
            }
    }
}
