import Foundation
import Observation

enum SessionState: Equatable {
    case bootstrapping
    case signedOut
    case signedIn
    case serviceUnavailable(message: String)
}

/// 只管理身份、连通性与实时会话，不暴露业务服务。
@Observable
@MainActor
final class AuthSession {
    private(set) var state: SessionState = .bootstrapping
    private(set) var phone = ""
    private(set) var currentUser: UserDTO?
    private(set) var backendReachable = false
    private(set) var backendStatusMessage = ""

    private let client: APIClient
    private let auth: AuthService
    private let realtime: ChatRealtime
    private let inbox: InboxState

    init(
        client: APIClient,
        auth: AuthService,
        realtime: ChatRealtime,
        inbox: InboxState
    ) {
        self.client = client
        self.auth = auth
        self.realtime = realtime
        self.inbox = inbox
        client.onUnauthorized = { [weak self] in
            self?.handleUnauthorized()
        }
    }

    var currentUserId: String? { currentUser?.id }
    var isLoggedIn: Bool { state == .signedIn }

    func bootstrap() async {
        state = .bootstrapping

        guard let token = client.authToken, !token.isEmpty else {
            // 未登录时才探活；已登录直接拉用户，避免启动连打 health + auth/me 触发限流
            await checkBackend()
            state = .signedOut
            return
        }

        do {
            currentUser = try await auth.fetchCurrentUser()
            phone = currentUser?.phone ?? ""
            state = .signedIn
            backendReachable = true
            backendStatusMessage = "已连接云端"
            // 未读放到后台，不阻塞进入主界面
            Task { await inbox.refresh(isAuthenticated: true) }
            connectRealtime()
        } catch APIError.unauthorized {
            handleUnauthorized()
            await checkBackend()
        } catch {
            currentUser = nil
            state = .serviceUnavailable(message: Self.friendlyBackendMessage(error))
        }
    }

    func login(phone: String, password: String) async throws {
        currentUser = try await auth.login(phone: phone, password: password)
        self.phone = phone
        state = .signedIn
        backendReachable = true
        backendStatusMessage = "已连接云端"
        Task { await inbox.refresh(isAuthenticated: true) }
        connectRealtime()
    }

    func register(
        phone: String,
        code: String,
        password: String,
        birthday: String,
        guardianConsent: Bool?
    ) async throws {
        currentUser = try await auth.register(
            phone: phone,
            code: code,
            password: password,
            birthday: birthday,
            guardianConsent: guardianConsent
        )
        self.phone = phone
        state = .signedIn
        backendReachable = true
        backendStatusMessage = "已连接云端"
        Task { await inbox.refresh(isAuthenticated: true) }
        connectRealtime()
    }

    func logout() async {
        realtime.disconnect()
        await auth.logout()
        state = .signedOut
        phone = ""
        currentUser = nil
        inbox.reset()
    }

    func checkBackend() async {
        do {
            backendReachable = try await client.healthCheck()
            backendStatusMessage = backendReachable ? "已连接云端" : "服务暂不可用"
        } catch {
            backendReachable = false
            backendStatusMessage = Self.friendlyBackendMessage(error)
        }
    }

    private func connectRealtime() {
        realtime.connect(token: client.authToken)
        realtime.onUnreadHint = { [weak self] in
            Task { await self?.inbox.refresh(isAuthenticated: self?.isLoggedIn == true) }
        }
    }

    private func handleUnauthorized() {
        realtime.disconnect()
        client.setAuthToken(nil)
        state = .signedOut
        phone = ""
        currentUser = nil
        inbox.reset()
    }

    private static func friendlyBackendMessage(_ error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.errorDescription ?? "无法连接服务器"
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .secureConnectionFailed, .serverCertificateUntrusted,
                 .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot:
                return "HTTPS 握手失败：请暂时关闭 Clash/VPN，或检查云端 nginx/证书"
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .timedOut:
                return "无法访问云端：请检查代理/网络，或确认服务器在线"
            case .notConnectedToInternet:
                return "当前设备没有网络连接"
            default:
                break
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? "无法连接服务器"
    }
}
