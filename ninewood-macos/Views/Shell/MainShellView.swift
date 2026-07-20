import SwiftUI

/// 主壳左侧导航，对齐 `docs/ui-renderings` 发现页侧栏：
/// 助手 / 主区 / 协作 / 账户；订单·钱包等嵌在「我的」二级导航，不平铺。
///
/// - 01 登录 / 02 注册：未登录态
/// - 侧栏一级：九木助手（置顶）、发现、卡池、发布、圈子、回、找人、消息、认证、帮助、我的
/// - 嵌套于「我的」：订单、需求、应标、钱包、服务卡、通知、福利、设置、关注、收藏、认证检索
/// - 认证中心 / 回仅侧栏一级，不在「我的」重复列出
/// - 25/26：订单内 Sheet，不进导航
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case discover          // 03
    case cardPool          // 04
    case publish           // 05
    case circles           // 06
    case loops             // 07
    case searchPeople      // 08
    /// 09 私聊 / 11 群聊：同一导航「消息」，页面内二级 Tab 切换
    case messages
    case cert              // 10 · 侧栏一级「认证」
    case profile           // 12 · 「我的」容器
    case help              // 21 · 侧栏一级「帮助」
    // —— 以下仅作深链 / 设计预览别名，嵌在 Profile 二级导航，不进主侧栏 ——
    case orders            // 13
    case myDemands         // 14
    case wallet            // 15
    case serviceCards      // 16
    case notifications     // 17
    case welfare           // 18
    /// 19 · 九木助手：主侧栏置顶「助手」区，不再嵌在「我的」
    case agent
    case settings          // 20
    case myBids            // 22
    case follows           // 23
    case favorites         // 24
    case providers

    var id: String { rawValue }

    /// 是否应进入「我的」二级导航，而非主侧栏平铺。
    var nestsUnderProfile: Bool {
        switch self {
        case .orders, .myDemands, .myBids, .wallet, .serviceCards,
             .notifications, .welfare, .settings,
             .follows, .favorites, .providers:
            true
        default:
            false
        }
    }

    /// 渲染图编号；登录/注册无编号入口。
    var renderingNumber: String? {
        switch self {
        case .discover: "03"
        case .cardPool: "04"
        case .publish: "05"
        case .circles: "06"
        case .loops: "07"
        case .searchPeople: "08"
        case .messages: "09"
        case .cert: "10"
        case .profile: "12"
        case .orders: "13"
        case .myDemands: "14"
        case .wallet: "15"
        case .serviceCards: "16"
        case .notifications: "17"
        case .welfare: "18"
        case .agent: "19"
        case .settings: "20"
        case .help: "21"
        case .myBids: "22"
        case .follows: "23"
        case .favorites: "24"
        case .providers: nil
        }
    }

    var title: String {
        switch self {
        case .discover: "发现"
        case .cardPool: "卡池"
        case .publish: "发布"
        case .circles: "圈子"
        case .loops: "回"
        case .searchPeople: "找人"
        case .messages: "消息"
        case .cert: "认证"
        case .profile: "我的"
        case .help: "帮助"
        case .orders: "订单"
        case .myDemands: "我的需求"
        case .wallet: "钱包与托管"
        case .serviceCards: "服务卡"
        case .notifications: "通知"
        case .welfare: "福利中心"
        case .agent: "九木助手"
        case .settings: "设置"
        case .myBids: "我的应标"
        case .follows: "关注与粉丝"
        case .favorites: "收藏"
        case .providers: "认证检索"
        }
    }

    var systemImage: String {
        switch self {
        case .discover: "house"
        case .cardPool: "square.stack.3d.up"
        case .publish: "doc.badge.plus"
        case .circles: "person.3"
        case .loops: "arrow.triangle.2.circlepath"
        case .searchPeople: "magnifyingglass"
        case .messages: "bubble.left.and.bubble.right"
        case .cert: "checkmark.shield"
        case .profile: "person"
        case .help: "questionmark.circle"
        case .orders: "checklist"
        case .myDemands: "doc.text"
        case .wallet: "creditcard"
        case .serviceCards: "rectangle.stack"
        case .notifications: "bell"
        case .welfare: "gift"
        case .agent: "sparkles"
        case .settings: "gearshape"
        case .myBids: "hand.raised"
        case .follows: "person.2"
        case .favorites: "star"
        case .providers: "person.badge.shield.checkmark"
        }
    }

    /// 深度链接 / 设计预览路径。
    var routePath: String {
        switch self {
        case .discover: "/discover"
        case .cardPool: "/card-pool"
        case .publish: "/publish"
        case .circles: "/circles"
        case .loops: "/loops/discover"
        case .searchPeople: "/search"
        case .messages: "/messages"
        case .cert: "/cert-center"
        case .profile: "/profile"
        case .help: "/help"
        case .orders: "/orders"
        case .myDemands: "/my-demands"
        case .wallet: "/transactions"
        case .serviceCards: "/service-cards"
        case .notifications: "/notifications"
        case .welfare: "/welfare"
        case .agent: "/agent"
        case .settings: "/settings"
        case .myBids: "/my-bids"
        case .follows: "/follows"
        case .favorites: "/favorites"
        case .providers: "/providers"
        }
    }

    static func from(path: String) -> SidebarItem? {
        // 回中心子路由统一归到侧栏「回」
        if path == "/loops" || path.hasPrefix("/loops/") {
            return .loops
        }
        switch path {
        case "/", "/discover": return .discover
        case "/publish", "/demands/create", "/service-cards/create": return .publish
        case "/messages", "/messages/group": return .messages
        case "/card-pool", "/card-pool/dead": return .cardPool
        case "/cert-center": return .cert
        case "/circles": return .circles
        case "/help": return .help
        case "/search": return .searchPeople
        case "/orders": return .orders
        case "/my-demands": return .myDemands
        case "/my-bids": return .myBids
        case "/transactions", "/wallet": return .wallet
        case "/service-cards": return .serviceCards
        case "/follows": return .follows
        case "/favorites": return .favorites
        case "/notifications": return .notifications
        case "/welfare": return .welfare
        case "/agent": return .agent
        case "/providers": return .providers
        case "/settings": return .settings
        case "/profile": return .profile
        default: return nil
        }
    }

    /// 侧栏置顶 · 九木助手（产品级入口，不嵌在「我的」）
    static let assistant: [SidebarItem] = [.agent]
    /// 渲染图侧栏 · 主区
    static let primary: [SidebarItem] = [.discover, .cardPool, .publish, .circles]
    /// 渲染图侧栏 · 协作（认证在账户区）
    static let collab: [SidebarItem] = [.loops, .searchPeople, .messages]
    /// 渲染图侧栏 · 账户（嵌套页不在此列）
    static let account: [SidebarItem] = [.cert, .help, .profile]
}

struct MainShellView: View {
    @Environment(AppSession.self) private var session
    var designPreviewDemands: [Demand]? = nil
    var designPreviewThreads: [ChatThread]? = nil
    var designPreviewBubbles: [ChatBubbleKind]? = nil
    var designPreviewPoolDemands: [Demand]? = nil
    var designPreviewOrders: [Order]? = nil
    var designPreviewUsers: [SoftUserDTO]? = nil
    var designPreviewGroupMessages = false
    var designPreviewCircles: [CircleDTO]? = nil
    var designPreviewLoopCollection: NaturalLoopRunCollection? = nil
    @State private var selection: SidebarItem = .discover
    @State private var activeProfilePath: String?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var detailRoute: AppDetailRoute?

    init(
        designPreviewDemands: [Demand]? = nil,
        designPreviewThreads: [ChatThread]? = nil,
        designPreviewBubbles: [ChatBubbleKind]? = nil,
        designPreviewPoolDemands: [Demand]? = nil,
        designPreviewOrders: [Order]? = nil,
        designPreviewUsers: [SoftUserDTO]? = nil,
        designPreviewGroupMessages: Bool = false,
        designPreviewCircles: [CircleDTO]? = nil,
        designPreviewLoopCollection: NaturalLoopRunCollection? = nil,
        initialSelection: SidebarItem = .discover,
        profileInitialPath: String? = nil,
        initialPath: String? = nil
    ) {
        self.designPreviewDemands = designPreviewDemands
        self.designPreviewThreads = designPreviewThreads
        self.designPreviewBubbles = designPreviewBubbles
        self.designPreviewPoolDemands = designPreviewPoolDemands
        self.designPreviewOrders = designPreviewOrders
        self.designPreviewUsers = designPreviewUsers
        self.designPreviewGroupMessages = designPreviewGroupMessages
        self.designPreviewCircles = designPreviewCircles
        self.designPreviewLoopCollection = designPreviewLoopCollection
        let resolved = Self.resolveEntry(initialSelection, profilePath: profileInitialPath)
        _selection = State(initialValue: resolved.selection)
        _activeProfilePath = State(initialValue: resolved.profilePath)
        self.bootstrapPath = initialPath ?? resolved.selection.routePath
    }

    /// 设计预览 / 深链入口：首帧同步到目标 path。
    private let bootstrapPath: String

    /// 嵌套页入口统一落到「我的」+ 二级 path。
    private static func resolveEntry(
        _ item: SidebarItem,
        profilePath: String?
    ) -> (selection: SidebarItem, profilePath: String?) {
        if item.nestsUnderProfile {
            return (.profile, profilePath ?? item.routePath)
        }
        if item == .profile {
            return (.profile, profilePath ?? "/profile")
        }
        return (item, nil)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                // 固定侧栏宽度，避免切换页面时列宽动画导致抖动/错位
                .navigationSplitViewColumnWidth(
                    min: 220,
                    ideal: AppTheme.sidebarWidth,
                    max: 280
                )
        } detail: {
            detail(for: selection)
                // 发布枢纽 / 回中心：selection 不变，靠 path 强制刷新
                .id(
                    selection == .publish || selection == .loops
                        ? session.navigation.currentPath
                        : selection.rawValue
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // 切换一级页时禁用隐式动画，避免列宽/内容过渡抖动
                .transaction { $0.animation = nil }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(AppTheme.primary)
        // 不自定义侧栏按钮：macOS NavigationSplitView 已自带一枚，再加会三连重复
        .task {
            if session.navigation.currentPath != bootstrapPath {
                _ = session.navigation.navigate(to: bootstrapPath)
            }
            await session.refreshUnread()
        }
        .onChange(of: session.navigation.request) { _, request in
            guard let request else { return }
            applyNavigation(request.path)
        }
        .onChange(of: session.navigation.currentPath) { _, path in
            // 同壳层内 publish / loops 子页：即使 request 观察偶发漏掉，也强制同步 selection
            if let item = SidebarItem.from(path: path), item == .publish || item == .loops {
                selection = item
            }
        }
        .sheet(item: $detailRoute) { route in
            NavigationStack {
                switch route {
                case .demand(let id):
                    DemandDetailLoaderView(demandID: id)
                case .order(let id):
                    OrderDetailLoaderView(orderID: id)
                }
            }
            .environment(session)
            .frame(minWidth: 720, minHeight: 640)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            brandHeader

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.space16) {
                    sidebarSection("助手", items: SidebarItem.assistant)
                    sidebarSection("主区", items: SidebarItem.primary)
                    sidebarSection("协作", items: SidebarItem.collab)
                    sidebarSection("账户", items: SidebarItem.account)
                }
                .padding(.horizontal, AppTheme.space8)
                .padding(.vertical, AppTheme.space16)
            }

            Divider()
            Button {
                Task { await session.logout() }
            } label: {
                Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(AppTheme.space16)
        }
        .background(AppTheme.surfaceLow)
    }

    private var brandHeader: some View {
        HStack(spacing: 12) {
            Image("NinewoodLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 46, height: 60)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("九木")
                    .font(.headline.weight(.semibold))
                Text("Ninewood")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.space16)
        .padding(.vertical, AppTheme.space16)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func sidebarSection(_ title: String, items: [SidebarItem]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, AppTheme.space8)
                .padding(.bottom, 2)

            ForEach(items) { item in
                sidebarRow(item)
            }
        }
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        let isSelected = selection == item
        return Button {
            if item == .profile {
                activeProfilePath = "/profile"
            }
            selection = item
            // 同步壳层路径，使「发布」枢纽 / 子工作区能按 currentPath 切换
            _ = session.navigation.navigate(to: item.routePath)
        } label: {
            HStack(spacing: AppTheme.space12) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20)
                Text(item.title)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                Spacer()
                if item == .messages, session.unreadMessageCount > 0 {
                    Text(session.unreadMessageCount > 99 ? "99+" : "\(session.unreadMessageCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.error, in: Capsule())
                }
            }
            .foregroundStyle(isSelected ? AppTheme.primary : Color.primary)
            .padding(.horizontal, AppTheme.space12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                isSelected ? AppTheme.softPrimary : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// 仅设计预览（`NINEWOOD_DESIGN_PREVIEW` / 显式注入）使用 fixtures；登录后主路径走真 API。
    private var isDesignPreviewMode: Bool {
        ProcessInfo.processInfo.environment["NINEWOOD_DESIGN_PREVIEW"] != nil
            || CommandLine.arguments.contains(where: { $0.hasSuffix("-design-preview") })
            || designPreviewDemands != nil
            || designPreviewOrders != nil
            || designPreviewThreads != nil
            || designPreviewUsers != nil
            || designPreviewCircles != nil
            || designPreviewLoopCollection != nil
            || designPreviewPoolDemands != nil
            || designPreviewGroupMessages
    }

    private var fixtureOrders: [Order]? {
        if let designPreviewOrders { return designPreviewOrders }
        return isDesignPreviewMode ? OrdersDesignPreviewFixtures.orders : nil
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        // 嵌套页一律进「我的」二级导航，避免主区再平铺一套
        if item.nestsUnderProfile {
            profileDetail(path: activeProfilePath ?? item.routePath)
        } else {
            switch item {
            case .discover:
                if let demands = designPreviewDemands ?? (isDesignPreviewMode ? DesignPreviewFixtures.demands : nil) {
                    DiscoverView(previewDemands: demands)
                } else {
                    DiscoverView(repository: session.demandRepository)
                }
            case .publish:
                publishWorkspace
            case .loops:
                LoopHubView(frontendPreview: isDesignPreviewMode)
                    .accessibilityIdentifier("loop-workspace-hub")
            case .messages:
                MessagesView(
                    repository: session.messageRepository,
                    previewThreads: designPreviewThreads ?? (isDesignPreviewMode ? MessagesDesignPreviewFixtures.threads : nil),
                    previewBubbles: designPreviewBubbles ?? (isDesignPreviewMode ? MessagesDesignPreviewFixtures.bubbles : nil),
                    previewMerges: isDesignPreviewMode ? MessagesDesignPreviewFixtures.merges : nil,
                    previewMergeBubbles: isDesignPreviewMode ? MessagesDesignPreviewFixtures.mergeBubbles : nil,
                    initialMode: designPreviewGroupMessages
                        || session.navigation.currentPath == "/messages/group"
                        ? .merge
                        : .direct
                )
            case .profile:
                profileDetail(path: activeProfilePath ?? "/profile")
            case .cardPool:
                CardPoolView(
                    previewDemands: designPreviewPoolDemands
                        ?? (isDesignPreviewMode ? DesignPreviewFixtures.demands : nil),
                    initialTab: session.navigation.currentPath == "/card-pool/dead"
                        ? CardPoolView.PoolTab.dead
                        : .active
                )
            case .circles:
                CirclesView(
                    previewCircles: designPreviewCircles
                        ?? (isDesignPreviewMode ? CirclesDesignPreviewFixtures.circles : nil)
                )
            case .cert:
                CertCenterView(preview: isDesignPreviewMode)
            case .help:
                HelpView()
            case .searchPeople:
                FindPeopleView(
                    previewUsers: designPreviewUsers
                        ?? (isDesignPreviewMode ? AccountDesignPreviewFixtures.users : nil)
                )
            case .agent:
                AgentChatView(
                    previewDetails: isDesignPreviewMode ? AgentDesignPreviewFixtures.details : nil
                )
            case .orders, .myDemands, .myBids, .wallet, .serviceCards,
                 .follows, .favorites, .notifications, .welfare,
                 .settings, .providers:
                profileDetail(path: activeProfilePath ?? item.routePath)
            }
        }
    }

    @ViewBuilder
    private var publishWorkspace: some View {
        // 显式读 currentPath，确保 Observable 订阅到导航变化
        let path = session.navigation.currentPath
        switch path {
        case "/demands/create":
            PublishCardWorkspaceView(mode: .demand, frontendPreview: isDesignPreviewMode)
                .accessibilityIdentifier("publish-workspace-demand")
        case "/service-cards/create":
            PublishCardWorkspaceView(mode: .service, frontendPreview: isDesignPreviewMode)
                .accessibilityIdentifier("publish-workspace-service")
        default:
            PublishHubView(frontendPreview: isDesignPreviewMode)
                .accessibilityIdentifier("publish-workspace-hub")
        }
    }

    private func profileDetail(path: String) -> some View {
        ProfileView(
            initialPath: path,
            previewOrders: fixtureOrders
        )
    }

    private func applyNavigation(_ path: String) {
        // 静态路由优先，避免 /demands/create 被当成需求 ID
        if let item = SidebarItem.from(path: path) {
            detailRoute = nil
            let resolved = Self.resolveEntry(item, profilePath: path)
            activeProfilePath = resolved.profilePath
            selection = resolved.selection
            return
        }

        if let id = resourceID(path, prefix: "/demands/"), Self.isResourceUUID(id) {
            detailRoute = .demand(id)
            return
        }
        if let id = resourceID(path, prefix: "/orders/") {
            detailRoute = .order(id)
            return
        }

        detailRoute = nil
    }

    private func resourceID(_ path: String, prefix: String) -> String? {
        guard path.hasPrefix(prefix) else { return nil }
        let id = String(path.dropFirst(prefix.count))
        return id.isEmpty || id.contains("/") ? nil : id
    }

    /// 需求资源 ID：排除 create/drafts 等保留段；UUID 或种子 ID 均可。
    private static func isResourceUUID(_ id: String) -> Bool {
        let reserved: Set<String> = ["create", "my", "search", "active", "dead", "drafts"]
        return !reserved.contains(id)
    }
}

private enum AppDetailRoute: Identifiable {
    case demand(String)
    case order(String)

    var id: String {
        switch self {
        case .demand(let id): "demand-\(id)"
        case .order(let id): "order-\(id)"
        }
    }
}

private struct OrderDetailLoaderView: View {
    let orderID: String
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var order: Order?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let order {
                OrderDetailView(
                    order: order,
                    currentUserID: session.currentUserId,
                    repository: session.orderRepository
                )
            } else if let errorMessage {
                NWEmptyState(
                    title: "订单加载失败",
                    systemImage: "wifi.exclamationmark",
                    message: errorMessage
                )
            } else {
                ProgressView("加载订单详情…")
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
                order = try await session.orderRepository.detail(id: orderID)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }
}
