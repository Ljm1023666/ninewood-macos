import SwiftUI

struct ContentView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Group {
            if let preview = DesignPreviewPage.current {
                preview.content
            } else {
                switch session.state {
                case .bootstrapping:
                    launchView
                case .signedOut:
                    LoginView(session: session)
                case .signedIn:
                    MainShellView()
                case let .serviceUnavailable(message):
                    serviceUnavailableView(message: message)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.state)
        .task {
            if DesignPreviewPage.current == nil {
                await session.bootstrap()
            }
        }
    }

    private var launchView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("正在连接九木云端…")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryLabel)
            Text("若长时间无响应，多半是请求过于频繁，请稍后再试")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.groupedBackground)
    }

    private func serviceUnavailableView(message: String) -> some View {
        ContentUnavailableView {
            Label("云端暂不可用", systemImage: "cloud.slash")
        } description: {
            Text("\(message)\n\n你的登录凭据仍安全保留。恢复连接后，九木会重新向云端确认账号和业务状态。")
        } actions: {
            Button("重新连接") {
                Task { await session.retryBootstrap() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(AppTheme.groupedBackground)
    }
}

/// Stable, authentication-free entry points for reproducing every reference page.
///
/// Use `NINEWOOD_DESIGN_PREVIEW=<slug>` or `--<slug>-design-preview`.
/// The numbered aliases mirror `docs/ui-renderings` so QA scripts do not need to
/// know the app's internal navigation names.
private enum DesignPreviewPage: String {
    case login, register, discover, cardPool = "card-pool", publish, circles, loops
    case loopsDiscover = "loops-discover", loopsMine = "loops-mine"
    case demandCreate = "demand-create", serviceCreate = "service-create"
    case findPeople = "find-people", messagesDirect = "messages-direct"
    case certification, messagesGroup = "messages-group", profile
    case orders, myDemands = "my-demands", wallet
    case serviceCards = "service-cards", notifications, welfare, agent, settings
    case help, myBids = "my-bids", follows, favorites
    case disputeSheet = "dispute-sheet", paymentSheet = "payment-sheet"

    static var current: Self? {
        let environmentValue = ProcessInfo.processInfo.environment["NINEWOOD_DESIGN_PREVIEW"]
        let argumentValue = CommandLine.arguments
            .first(where: { $0.hasSuffix("-design-preview") })
            .map { String($0.dropFirst(2).dropLast("-design-preview".count)) }
        let rawValue = environmentValue ?? argumentValue
        guard let rawValue else { return nil }

        let aliases: [String: Self] = [
            "01": .login, "01-login": .login,
            "02": .register, "02-register": .register,
            "03": .discover, "03-discover": .discover,
            "04": .cardPool, "04-card-pool": .cardPool,
            "05": .publish, "05-publish": .publish,
            "05a": .demandCreate, "05-demand-create": .demandCreate, "demand-create": .demandCreate,
            "05b": .serviceCreate, "05-service-create": .serviceCreate, "service-create": .serviceCreate,
            "06": .circles, "06-circles": .circles,
            "07": .loops, "07-natural-loop": .loops, "loops": .loops,
            "07a": .loopsDiscover, "loops-discover": .loopsDiscover, "loop-discover": .loopsDiscover,
            "07b": .loopsMine, "loops-mine": .loopsMine, "loop-mine": .loopsMine,
            "08": .findPeople, "08-find-people": .findPeople,
            "09": .messagesDirect, "09-messages-direct": .messagesDirect,
            "10": .certification, "10-certification": .certification,
            "11": .messagesGroup, "11-messages-group": .messagesGroup,
            "12": .profile, "12-profile": .profile,
            "13": .orders, "13-orders": .orders,
            "14": .myDemands, "14-my-demands": .myDemands,
            "15": .wallet, "15-wallet": .wallet,
            "16": .serviceCards, "16-service-cards": .serviceCards,
            "17": .notifications, "17-notifications": .notifications,
            "18": .welfare, "18-welfare": .welfare,
            "19": .agent, "19-agent": .agent,
            "20": .settings, "20-settings": .settings,
            "21": .help, "21-help": .help,
            "22": .myBids, "22-my-bids": .myBids,
            "23": .follows, "23-follows": .follows,
            "24": .favorites, "24-favorites": .favorites,
            "25": .disputeSheet, "25-dispute-sheet": .disputeSheet,
            "26": .paymentSheet, "26-payment-sheet": .paymentSheet,
            // Backward-compatible aliases used by the original QA pass.
            "messages": .messagesDirect
        ]
        return aliases[rawValue] ?? Self(rawValue: rawValue)
    }

    @ViewBuilder
    var content: some View {
        switch self {
        case .login:
            AuthReferencePreview(mode: .login)
        case .register:
            AuthReferencePreview(mode: .register)
        case .discover:
            MainShellView(designPreviewDemands: DesignPreviewFixtures.demands)
        case .messagesDirect:
            MainShellView(
                designPreviewThreads: MessagesDesignPreviewFixtures.threads,
                designPreviewBubbles: MessagesDesignPreviewFixtures.bubbles,
                initialSelection: .messages
            )
        case .messagesGroup:
            // 11 与 09 共用侧栏「消息」，仅初始二级 Tab 为群聊
            MainShellView(
                designPreviewThreads: MessagesDesignPreviewFixtures.threads,
                designPreviewBubbles: MessagesDesignPreviewFixtures.bubbles,
                designPreviewGroupMessages: true,
                initialSelection: .messages
            )
        case .cardPool:
            MainShellView(
                designPreviewPoolDemands: CardPoolDesignPreviewFixtures.demands,
                initialSelection: .cardPool
            )
        case .publish:
            MainShellView(initialSelection: .publish, initialPath: "/publish")
        case .demandCreate:
            MainShellView(initialSelection: .publish, initialPath: "/demands/create")
        case .serviceCreate:
            MainShellView(initialSelection: .publish, initialPath: "/service-cards/create")
        case .circles:
            MainShellView(designPreviewCircles: CirclesDesignPreviewFixtures.circles, initialSelection: .circles)
        case .loops:
            MainShellView(initialSelection: .loops, initialPath: "/loops/discover")
        case .loopsDiscover:
            MainShellView(initialSelection: .loops, initialPath: "/loops/discover")
        case .loopsMine:
            MainShellView(initialSelection: .loops, initialPath: "/loops/mine")
        case .findPeople:
            MainShellView(designPreviewUsers: AccountDesignPreviewFixtures.users, initialSelection: .searchPeople)
        case .certification:
            MainShellView(designPreviewUsers: AccountDesignPreviewFixtures.users, initialSelection: .cert)
        case .help:
            MainShellView(initialSelection: .help)
        case .profile:
            MainShellView(
                designPreviewOrders: OrdersDesignPreviewFixtures.orders,
                initialSelection: .profile,
                profileInitialPath: "/profile"
            )
        case .orders:
            MainShellView(
                designPreviewOrders: OrdersDesignPreviewFixtures.orders,
                initialSelection: .profile,
                profileInitialPath: "/orders"
            )
        case .myDemands:
            MainShellView(
                designPreviewOrders: OrdersDesignPreviewFixtures.orders,
                initialSelection: .profile,
                profileInitialPath: "/my-demands"
            )
        case .wallet:
            MainShellView(
                designPreviewOrders: OrdersDesignPreviewFixtures.orders,
                initialSelection: .profile,
                profileInitialPath: "/transactions"
            )
        case .serviceCards:
            MainShellView(
                designPreviewOrders: OrdersDesignPreviewFixtures.orders,
                initialSelection: .profile,
                profileInitialPath: "/service-cards"
            )
        case .notifications:
            MainShellView(
                designPreviewOrders: OrdersDesignPreviewFixtures.orders,
                initialSelection: .profile,
                profileInitialPath: "/notifications"
            )
        case .welfare:
            MainShellView(
                designPreviewOrders: OrdersDesignPreviewFixtures.orders,
                initialSelection: .profile,
                profileInitialPath: "/welfare"
            )
        case .agent:
            MainShellView(
                designPreviewOrders: OrdersDesignPreviewFixtures.orders,
                initialSelection: .agent
            )
        case .settings:
            MainShellView(initialSelection: .profile, profileInitialPath: "/settings")
        case .myBids:
            MainShellView(
                designPreviewOrders: OrdersDesignPreviewFixtures.orders,
                initialSelection: .profile,
                profileInitialPath: "/my-bids"
            )
        case .follows:
            MainShellView(
                designPreviewOrders: OrdersDesignPreviewFixtures.orders,
                designPreviewUsers: AccountDesignPreviewFixtures.users,
                initialSelection: .profile,
                profileInitialPath: "/follows"
            )
        case .favorites:
            MainShellView(
                designPreviewOrders: OrdersDesignPreviewFixtures.orders,
                initialSelection: .profile,
                profileInitialPath: "/favorites"
            )
        case .disputeSheet:
            TransactionSheetDesignPreview(kind: .dispute)
        case .paymentSheet:
            PaymentPrepayDesignPreview()
        }
    }
}

#Preview {
    ContentView()
        .environment(AppSession())
}
