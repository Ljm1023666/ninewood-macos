import Foundation

/// 应用依赖容器。服务的构造与身份状态分离，避免 Session 演变为服务定位器。
@MainActor
final class ServiceRegistry {
    let apiClient: APIClient
    let auth: AuthService
    let demands: DemandService
    let orders: OrderService
    let messages: MessageService
    let wallet: WalletService
    let users: UserService
    let loops: LoopService
    let naturalLoops: NaturalLoopRepository
    let serviceCards: ServiceCardService
    let reviews: ReviewService
    let regions: RegionService
    let tags: TagService
    let certification: CertificationService
    let captcha: CaptchaService
    let circles: CircleService
    let welfare: WelfareService
    let agent: AgentService
    let chatRealtime: ChatRealtime

    convenience init() {
        self.init(apiClient: APIClient())
    }

    init(apiClient: APIClient) {
        self.apiClient = apiClient
        self.auth = AuthService(client: apiClient)
        self.demands = DemandService(client: apiClient)
        self.orders = OrderService(client: apiClient)
        self.messages = MessageService(client: apiClient)
        self.wallet = WalletService(client: apiClient)
        self.users = UserService(client: apiClient)
        self.loops = LoopService(client: apiClient)
        self.naturalLoops = NaturalLoopRepository(service: self.loops)
        self.serviceCards = ServiceCardService(client: apiClient)
        self.reviews = ReviewService(client: apiClient)
        self.regions = RegionService(client: apiClient)
        self.tags = TagService(client: apiClient)
        self.certification = CertificationService(client: apiClient)
        self.captcha = CaptchaService(client: apiClient)
        self.circles = CircleService(client: apiClient)
        self.welfare = WelfareService(client: apiClient)
        self.agent = AgentService(client: apiClient)
        self.chatRealtime = ChatRealtime()
    }
}
