import SwiftUI

struct ProfileView: View {
    @Environment(AppSession.self) private var session
    @State private var selection: ProfileNav = .overview

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
            case .wallet: "creditcard"
            case .orders: "checklist"
            case .myDemands: "doc.text"
            case .myBids: "hand.raised"
            case .serviceCards: "rectangle.stack"
            case .cert: "checkmark.shield"
            case .providers: "person.badge.shield.checkmark"
            case .follows: "person.2"
            case .favorites: "star"
            case .notifications: "bell"
            case .loops: "arrow.triangle.2.circlepath"
            case .welfare: "gift"
            case .agent: "sparkles"
            case .settings: "gearshape"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            navPane
                .paneColumn(minWidth: 220, idealWidth: 260)

            Divider()

            destination(selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("我的")
    }

    /// 不用 List：嵌套在 NavigationSplitView detail 里时 macOS List 行经常吞点击。
    private var navPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                profileHeaderButton
                    .padding(.bottom, 8)

                navSection("交易", [.orders, .myDemands, .myBids, .wallet])
                navSection("服务与认证", [.serviceCards, .cert, .providers])
                navSection("社交", [.follows, .favorites, .notifications, .loops, .welfare])
                navSection("其他", [.agent, .settings])
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppTheme.workspaceBackground)
    }

    private var profileHeaderButton: some View {
        let name = session.currentUser?.nickname ?? "九木用户"
        let score = session.currentUser?.creditScore ?? 60
        let selected = selection == .overview

        return Button {
            selection = .overview
        } label: {
            HStack(spacing: 10) {
                NWAvatarView(
                    url: session.currentUser?.avatarMediaURL,
                    name: name,
                    size: 40
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Text("信用分 \(score)")
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
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 4)

            ForEach(items) { item in
                navButton(item)
            }
        }
    }

    private func navButton(_ item: ProfileNav) -> some View {
        let selected = selection == item
        return Button {
            selection = item
        } label: {
            Label(item.title, systemImage: item.systemImage)
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
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
        let name = session.currentUser?.nickname ?? "九木用户"
        let score = session.currentUser?.creditScore ?? 60

        return ZStack(alignment: .bottomLeading) {
            NWRemoteImage(
                url: session.currentUser?.coverMediaURL,
                cornerRadius: 0,
                systemFallback: "person.crop.rectangle",
                fit: .fill
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .allowsHitTesting(false)

            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: AppTheme.space12) {
                HStack(alignment: .center, spacing: 14) {
                    NWAvatarView(
                        url: session.currentUser?.avatarMediaURL,
                        name: name,
                        size: 72
                    )
                    .overlay {
                        Circle().stroke(.white.opacity(0.9), lineWidth: 2)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(name)
                            .font(.title.bold())
                            .foregroundStyle(.white)
                        Text("信用分 \(score)")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                        NWStatusChip(text: session.currentUser?.certificationLevel ?? "NONE")
                    }
                    Spacer(minLength: 0)
                }

                Text("从左侧选择一项查看详情")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(AppTheme.space24)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func destination(_ item: ProfileNav) -> some View {
        switch item {
        case .overview:
            overviewPane
        case .wallet:
            WalletView()
        case .orders:
            OrdersListView()
        case .loops:
            NaturalLoopWorkspaceView()
        case .cert:
            CertCenterView()
        case .myDemands:
            MyDemandsView()
        case .myBids:
            MyBidsView()
        case .serviceCards:
            ServiceCardsManageView()
        case .follows:
            FollowsView()
        case .favorites:
            FavoritesView()
        case .notifications:
            NotificationsView()
        case .providers:
            ProvidersSearchView()
        case .welfare:
            WelfareCenterView()
        case .agent:
            AgentChatView()
        case .settings:
            SettingsView()
        }
    }
}
