import XCTest
@testable import NinewoodAPIContracts

@MainActor
final class InboxStateTests: XCTestCase {
    func testRefreshLoadsUnreadCountAndClearsError() async {
        let source = UnreadCountStub()
        source.result = .success(7)
        let inbox = InboxState(messages: source)

        await inbox.refresh(isAuthenticated: true)

        XCTAssertEqual(inbox.unreadMessageCount, 7)
        XCTAssertNil(inbox.lastError)
    }

    func testSignedOutRefreshResetsStateWithoutRequest() async {
        let source = UnreadCountStub()
        source.result = .success(5)
        let inbox = InboxState(messages: source)
        await inbox.refresh(isAuthenticated: true)

        await inbox.refresh(isAuthenticated: false)

        XCTAssertEqual(inbox.unreadMessageCount, 0)
        XCTAssertNil(inbox.lastError)
        XCTAssertEqual(source.callCount, 1)
    }

    func testRateLimitKeepsPreviousCountWithoutShowingError() async {
        let source = UnreadCountStub()
        source.result = .success(4)
        let inbox = InboxState(messages: source)
        await inbox.refresh(isAuthenticated: true)

        source.result = .failure(APIError.rateLimited(retryAfter: 10, requestID: "rate"))
        await inbox.refresh(isAuthenticated: true)

        XCTAssertEqual(inbox.unreadMessageCount, 4)
        XCTAssertNil(inbox.lastError)
    }

    func testOtherFailureKeepsCountAndExposesFriendlyError() async {
        let source = UnreadCountStub()
        source.result = .success(3)
        let inbox = InboxState(messages: source)
        await inbox.refresh(isAuthenticated: true)

        source.result = .failure(InboxTestError.failed)
        await inbox.refresh(isAuthenticated: true)

        XCTAssertEqual(inbox.unreadMessageCount, 3)
        XCTAssertEqual(inbox.lastError, "未读加载失败")
    }

    func testLocalReadNeverDropsBelowZero() async {
        let source = UnreadCountStub()
        source.result = .success(2)
        let inbox = InboxState(messages: source)
        await inbox.refresh(isAuthenticated: true)

        inbox.applyLocalRead(count: 5)
        XCTAssertEqual(inbox.unreadMessageCount, 0)
        inbox.applyLocalRead(count: -1)
        XCTAssertEqual(inbox.unreadMessageCount, 0)
    }
}

@MainActor
private final class UnreadCountStub: MessageUnreadCounting {
    var result: Result<Int, Error> = .success(0)
    private(set) var callCount = 0

    func unreadCount() async throws -> Int {
        callCount += 1
        return try result.get()
    }
}

private enum InboxTestError: LocalizedError {
    case failed
    var errorDescription: String? { "未读加载失败" }
}
