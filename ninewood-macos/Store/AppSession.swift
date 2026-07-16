import Foundation
import Observation

/// 迁移期兼容门面。新功能应依赖 AuthSession、InboxState 或具体 Repository；
/// 旧视图可继续通过这些只读代理访问服务，直至逐个迁移完成。
@Observable
@MainActor
final class AppSession {
    let dependencies: ServiceRegistry
    let authSession: AuthSession
    let inbox: InboxState

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
    var serviceCardService: ServiceCardService { dependencies.serviceCards }
    var reviewService: ReviewService { dependencies.reviews }
    var regionService: RegionService { dependencies.regions }
    var tagService: TagService { dependencies.tags }
    var certificationService: CertificationService { dependencies.certification }
    var captchaService: CaptchaService { dependencies.captcha }
    var circleService: CircleService { dependencies.circles }
    var welfareService: WelfareService { dependencies.welfare }
    var agentService: AgentService { dependencies.agent }
    var chatRealtime: ChatRealtime { dependencies.chatRealtime }

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
