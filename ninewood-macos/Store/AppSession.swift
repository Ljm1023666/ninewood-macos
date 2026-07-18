import Foundation
import Observation

struct AppNavigationRequest: Identifiable, Hashable {
    let id = UUID()
    let path: String
}

@Observable
@MainActor
final class AppNavigationState {
    private(set) var request: AppNavigationRequest?
    private(set) var currentPath = "/discover"
    private(set) var pendingDirectPeerID: String?

    @discardableResult
    func navigate(to rawPath: String) -> Bool {
        let path = normalized(alias(normalized(rawPath)))
        guard Self.supports(path) else { return false }
        currentPath = path
        request = AppNavigationRequest(path: path)
        return true
    }

    /// 兼容别名路径
    private func alias(_ path: String) -> String {
        switch path {
        case "/wallet": return "/transactions"
        default: return path
        }
    }

    func openDirectMessage(peerID: String) {
        pendingDirectPeerID = peerID
        navigate(to: "/messages")
    }

    var hasPendingDirectPeer: Bool { pendingDirectPeerID != nil }

    func consumePendingDirectPeerID() -> String? {
        defer { pendingDirectPeerID = nil }
        return pendingDirectPeerID
    }

    private func normalized(_ rawPath: String) -> String {
        let withoutQuery = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawPath
        guard withoutQuery.count > 1 else { return "/" }
        return withoutQuery.hasSuffix("/") ? String(withoutQuery.dropLast()) : withoutQuery
    }

    private static func supports(_ path: String) -> Bool {
        let staticPaths: Set<String> = [
            "/", "/discover", "/demands/create", "/my-demands", "/orders",
            "/settings", "/help", "/messages", "/card-pool", "/card-pool/dead",
            "/cert-center", "/circles", "/welfare", "/search", "/profile",
            "/agent", "/transactions", "/wallet", "/my-bids", "/service-cards",
            "/notifications", "/follows", "/favorites", "/loops",
            "/providers", "/messages/group"
        ]
        if staticPaths.contains(path) { return true }
        if path.hasPrefix("/demands/"), path.split(separator: "/").count == 2 {
            let id = path.split(separator: "/").last.map(String.init) ?? ""
            // 保留字不是资源 ID
            if ["create", "my", "search", "active", "dead", "drafts"].contains(id) { return false }
            return true
        }
        if path.hasPrefix("/orders/"), path.split(separator: "/").count == 2 { return true }
        return false
    }
}

/// 迁移期兼容门面。新功能应依赖 AuthSession、InboxState 或具体 Repository；
/// 旧视图可继续通过这些只读代理访问服务，直至逐个迁移完成。
@Observable
@MainActor
final class AppSession {
    let dependencies: ServiceRegistry
    let authSession: AuthSession
    let inbox: InboxState
    let navigation = AppNavigationState()

    var state: SessionState { authSession.state }
    var phone: String { authSession.phone }
    var currentUser: UserDTO? { authSession.currentUser }
    var backendReachable: Bool { authSession.backendReachable }
    var backendStatusMessage: String { authSession.backendStatusMessage }
    var unreadMessageCount: Int { inbox.unreadMessageCount }

    var apiClient: APIClient { dependencies.apiClient }
    var authService: AuthService { dependencies.auth }
    var demandService: DemandService { dependencies.demands }
    var orderService: OrderService { dependencies.orders }
    var messageService: MessageService { dependencies.messages }
    var walletService: WalletService { dependencies.wallet }
    var userService: UserService { dependencies.users }
    var loopService: LoopService { dependencies.loops }
    var naturalLoopRepository: NaturalLoopRepository { dependencies.naturalLoops }
    var demandRepository: DemandRepository { dependencies.demandRepository }
    var orderRepository: OrderRepository { dependencies.orderRepository }
    var messageRepository: MessageRepository { dependencies.messageRepository }
    var userRepository: UserRepository { dependencies.userRepository }
    var serviceCardService: ServiceCardService { dependencies.serviceCards }
    var reviewService: ReviewService { dependencies.reviews }
    var regionService: RegionService { dependencies.regions }
    var tagService: TagService { dependencies.tags }
    var demandPublishRepository: DemandPublishRepository { dependencies.demandPublishing }
    var certificationService: CertificationService { dependencies.certification }
    var captchaService: CaptchaService { dependencies.captcha }
    var circleService: CircleService { dependencies.circles }
    var welfareService: WelfareService { dependencies.welfare }
    var agentService: AgentService { dependencies.agent }
    var chatRealtime: ChatRealtime { dependencies.chatRealtime }
    var reportService: ReportService { dependencies.reports }

    init(dependencies: ServiceRegistry? = nil) {
        let registry = dependencies ?? ServiceRegistry()
        let inbox = InboxState(messages: registry.messages)
        self.dependencies = registry
        self.inbox = inbox
        self.authSession = AuthSession(
            client: registry.apiClient,
            auth: registry.auth,
            realtime: registry.chatRealtime,
            inbox: inbox
        )
    }

    var currentUserId: String? { authSession.currentUserId }
    var isLoggedIn: Bool { authSession.isLoggedIn }

    func bootstrap() async {
        await authSession.bootstrap()
    }

    func checkBackend() async {
        await authSession.checkBackend()
    }

    func login(phone: String, password: String) async throws {
        try await authSession.login(phone: phone, password: password)
    }

    func register(
        phone: String,
        code: String,
        password: String,
        birthday: String,
        guardianConsent: Bool?
    ) async throws {
        try await authSession.register(
            phone: phone,
            code: code,
            password: password,
            birthday: birthday,
            guardianConsent: guardianConsent
        )
    }

    func sendRegistrationCode(phone: String) async throws -> SendCodeResultDTO {
        let token = try await captchaService.obtainSendCodeToken()
        return try await authService.sendCode(phone: phone, captchaToken: token)
    }

    func logout() async {
        await authSession.logout()
    }

    func refreshUnread() async {
        await inbox.refresh(isAuthenticated: isLoggedIn)
    }

    func applyLocalRead(count: Int) {
        inbox.applyLocalRead(count: count)
    }

    func retryBootstrap() async {
        await authSession.bootstrap()
    }
}
