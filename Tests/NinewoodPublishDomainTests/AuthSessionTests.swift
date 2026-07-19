import Foundation
import XCTest
@testable import NinewoodAPIContracts

@MainActor
final class AuthSessionTests: XCTestCase {
    override func tearDown() {
        URLProtocolAuthStub.handler = nil
        super.tearDown()
    }

    func testBootstrapWithoutTokenChecksBackendAndSignsOut() async {
        let context = makeContext(token: nil)
        URLProtocolAuthStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/health/services")
            return Self.response(request, status: 200, body: #"{"status":"healthy"}"#)
        }

        await context.session.bootstrap()

        XCTAssertEqual(context.session.state, .signedOut)
        XCTAssertTrue(context.session.backendReachable)
        XCTAssertEqual(context.auth.fetchCount, 0)
        XCTAssertEqual(context.realtime.connectTokens.count, 0)
    }

    func testBootstrapWithTokenRestoresUserAndRealtime() async {
        let context = makeContext(token: "saved-token")
        context.auth.fetchResult = .success(makeAuthUser())

        await context.session.bootstrap()

        XCTAssertEqual(context.session.state, .signedIn)
        XCTAssertEqual(context.session.phone, "13800000000")
        XCTAssertEqual(context.session.currentUserId, "user-1")
        XCTAssertEqual(context.realtime.connectTokens, ["saved-token"])
    }

    func testUnauthorizedBootstrapClearsSessionAndDisconnectsRealtime() async {
        let context = makeContext(token: "expired-token")
        context.auth.fetchResult = .failure(APIError.unauthorized)
        URLProtocolAuthStub.handler = { request in
            Self.response(request, status: 200, body: #"{"status":"healthy"}"#)
        }

        await context.session.bootstrap()

        XCTAssertEqual(context.session.state, .signedOut)
        XCTAssertNil(context.client.authToken)
        XCTAssertEqual(context.realtime.disconnectCount, 1)
        XCTAssertTrue(context.session.backendReachable)
    }

    func testLoginConnectsRealtimeAndLogoutResetsIdentity() async throws {
        let context = makeContext(token: nil)
        context.auth.loginResult = .success(makeAuthUser())

        try await context.session.login(phone: "13800000000", password: "password")
        XCTAssertEqual(context.session.state, .signedIn)
        XCTAssertEqual(context.session.phone, "13800000000")

        await context.session.logout()

        XCTAssertEqual(context.session.state, .signedOut)
        XCTAssertEqual(context.session.phone, "")
        XCTAssertNil(context.session.currentUser)
        XCTAssertEqual(context.auth.logoutCount, 1)
        XCTAssertGreaterThanOrEqual(context.realtime.disconnectCount, 1)
    }

    func testAPIClientUnauthorizedCallbackImmediatelySignsOut() async throws {
        let context = makeContext(token: "active-token")
        context.auth.loginResult = .success(makeAuthUser())
        try await context.session.login(phone: "13800000000", password: "password")
        XCTAssertEqual(context.session.state, .signedIn)

        context.client.onUnauthorized?()

        XCTAssertEqual(context.session.state, .signedOut)
        XCTAssertNil(context.client.authToken)
        XCTAssertNil(context.session.currentUser)
    }

    private func makeContext(token: String?) -> AuthTestContext {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolAuthStub.self]
        let tokenStore = AuthMemoryTokenStore(token: token)
        let client = APIClient(
            session: URLSession(configuration: configuration),
            tokenStore: tokenStore
        )
        let auth = AuthServiceStub()
        let realtime = RealtimeSessionStub()
        let unread = UnreadSourceStub()
        let inbox = InboxState(messages: unread)
        let session = AuthSession(
            client: client,
            auth: auth,
            realtime: realtime,
            inbox: inbox
        )
        return AuthTestContext(
            client: client,
            auth: auth,
            realtime: realtime,
            session: session
        )
    }

    private static func response(
        _ request: URLRequest,
        status: Int,
        body: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!,
            Data(body.utf8)
        )
    }
}

@MainActor
private struct AuthTestContext {
    let client: APIClient
    let auth: AuthServiceStub
    let realtime: RealtimeSessionStub
    let session: AuthSession
}

@MainActor
private final class AuthServiceStub: AuthServicing {
    var fetchResult: Result<UserDTO, Error> = .failure(APIError.unauthorized)
    var loginResult: Result<UserDTO, Error> = .failure(APIError.unauthorized)
    var registerResult: Result<UserDTO, Error> = .failure(APIError.unauthorized)
    private(set) var fetchCount = 0
    private(set) var logoutCount = 0

    func login(phone: String, password: String) async throws -> UserDTO {
        try loginResult.get()
    }

    func register(
        phone: String,
        code: String,
        password: String,
        birthday: String,
        guardianConsent: Bool?
    ) async throws -> UserDTO {
        try registerResult.get()
    }

    func fetchCurrentUser() async throws -> UserDTO {
        fetchCount += 1
        return try fetchResult.get()
    }

    func logout() async {
        logoutCount += 1
    }
}

@MainActor
private final class RealtimeSessionStub: RealtimeSessionConnecting {
    var onUnreadHint: (() -> Void)?
    private(set) var connectTokens: [String] = []
    private(set) var disconnectCount = 0

    func connect(token: String?) {
        if let token { connectTokens.append(token) }
    }

    func disconnect() {
        disconnectCount += 1
    }
}

@MainActor
private final class UnreadSourceStub: MessageUnreadCounting {
    func unreadCount() async throws -> Int { 0 }
}

private final class AuthMemoryTokenStore: APITokenStore {
    var token: String?
    init(token: String?) { self.token = token }
    func load() -> String? { token }
    func save(_ token: String) { self.token = token }
    func delete() { token = nil }
}

private final class URLProtocolAuthStub: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeAuthUser() -> UserDTO {
    UserDTO(
        id: "user-1",
        phone: "13800000000",
        nickname: "测试用户",
        avatarUrl: nil,
        coverUrl: nil,
        demandCardCoverUrl: nil,
        creditScore: 80,
        certificationLevel: nil,
        completedOrders: 2
    )
}
