import Foundation
import XCTest
@testable import NinewoodAPIContracts

@MainActor
final class FeatureModelTests: XCTestCase {
    func testDiscoverLoadsNearbyParametersAndSelectsFirstDemand() async {
        let repository = DemandRepositoryStub()
        repository.result = .success([makeDemand(id: "one"), makeDemand(id: "two")])
        let model = DiscoverFeatureModel(repository: repository)

        await model.load(keyword: "设计", nearbyOnly: true)

        XCTAssertEqual(model.demands.map(\.id), ["one", "two"])
        XCTAssertEqual(model.selectedDemand?.id, "one")
        XCTAssertEqual(repository.lastKeyword, "设计")
        XCTAssertEqual(repository.lastLatitude, 31.2304)
        XCTAssertEqual(repository.lastLongitude, 121.4737)
        XCTAssertEqual(repository.lastDistance, 20)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
    }

    func testDiscoverRefreshKeepsSelectionAndClearsRowsOnFailure() async {
        let repository = DemandRepositoryStub()
        repository.result = .success([makeDemand(id: "one"), makeDemand(id: "two")])
        let model = DiscoverFeatureModel(repository: repository)
        await model.load()
        model.selectedDemand = model.demands[1]

        repository.result = .success([makeDemand(id: "two"), makeDemand(id: "three")])
        await model.load()
        XCTAssertEqual(model.selectedDemand?.id, "two")

        repository.result = .failure(FeatureTestError.failed)
        await model.load()
        XCTAssertTrue(model.demands.isEmpty)
        XCTAssertNil(model.selectedDemand)
        XCTAssertEqual(model.errorMessage, "测试失败")
    }

    func testOrdersPassesRoleAndPreservesSelectionAcrossRefresh() async {
        let repository = OrderRepositoryStub()
        repository.result = .success([
            makeOrder(id: "one", stage: .inProgress),
            makeOrder(id: "two", stage: .waitingReview)
        ])
        let model = OrdersFeatureModel(repository: repository)
        model.roleFilter = .provider
        await model.load()
        model.selected = model.orders[1]

        repository.result = .success([
            makeOrder(id: "two", stage: .completed),
            makeOrder(id: "three", stage: .disputed)
        ])
        await model.load()

        XCTAssertEqual(repository.lastRole, "provider")
        XCTAssertEqual(model.selected?.id, "two")
        model.filter = .completed
        XCTAssertEqual(model.filteredOrders.map(\.id), ["two"])
    }

    func testOrdersFailureRetainsLastSuccessfulRows() async {
        let repository = OrderRepositoryStub()
        repository.result = .success([makeOrder(id: "one", stage: .accepted)])
        let model = OrdersFeatureModel(repository: repository)
        await model.load()

        repository.result = .failure(FeatureTestError.failed)
        await model.load()

        XCTAssertEqual(model.orders.map(\.id), ["one"])
        XCTAssertEqual(model.errorMessage, "测试失败")
        XCTAssertFalse(model.isLoading)
    }

    func testMessagesLoadSearchAndUnreadLifecycle() async {
        let repository = ConversationRepositoryStub()
        repository.result = .success([
            makeThread(id: "one", name: "小林", preview: "设计稿", unread: 3),
            makeThread(id: "two", name: "阿木", preview: "订单进度", unread: 1)
        ])
        let model = MessagesFeatureModel(repository: repository)
        await model.load()

        XCTAssertEqual(model.selected?.id, "one")
        model.searchText = "订单"
        XCTAssertEqual(model.filteredThreads.map(\.id), ["two"])
        XCTAssertEqual(model.clearUnread(threadID: "one"), 3)
        XCTAssertEqual(model.selected?.unreadCount, 0)

        await model.load()
        XCTAssertEqual(model.selected?.unreadCount, 0)
    }

    func testIncomingMessageMovesThreadToTopAndIncrementsUnread() async {
        let repository = ConversationRepositoryStub()
        repository.result = .success([
            makeThread(id: "one", name: "一号", preview: "旧消息"),
            makeThread(id: "two", name: "二号", preview: "旧消息")
        ])
        let model = MessagesFeatureModel(repository: repository)
        await model.load()

        model.applyIncomingPreview(
            RealtimeIncomingMessage(
                id: "message",
                fromUserId: "two",
                toUserId: "me",
                content: "新进度",
                createdAt: Date(),
                hasCardAttachment: false,
                mergeId: nil
            ),
            currentUserID: "me"
        )

        XCTAssertEqual(model.filteredThreads.first?.id, "two")
        XCTAssertEqual(model.filteredThreads.first?.preview, "新进度")
        XCTAssertEqual(model.filteredThreads.first?.unreadCount, 1)
    }

    func testStickyMessageFocusSurvivesRefreshWithoutServerThread() async {
        let repository = ConversationRepositoryStub()
        repository.result = .success([makeThread(id: "one", name: "一号", preview: "旧消息")])
        let model = MessagesFeatureModel(repository: repository)
        await model.load()

        await model.focusPeer("new-peer") {
            SoftUserDTO(
                id: "new-peer",
                phone: nil,
                nickname: "新联系人",
                avatarUrl: nil,
                coverUrl: nil,
                demandCardCoverUrl: nil,
                creditScore: 60,
                completedOrders: 0
            )
        }
        await model.load()

        XCTAssertEqual(model.selected?.peer.id, "new-peer")
        XCTAssertEqual(model.filteredThreads.first?.peer.name, "新联系人")
    }

    func testLatestMessageRefreshWinsWhenEarlierRequestFinishesLast() async {
        let repository = DeferredConversationRepositoryStub()
        let model = MessagesFeatureModel(repository: repository)

        let firstLoad = Task { await model.load() }
        await waitForPendingRequests(repository, count: 1)
        let secondLoad = Task { await model.load() }
        await waitForPendingRequests(repository, count: 2)

        repository.succeedRequest(at: 1, with: [
            makeThread(id: "newest", name: "新结果", preview: "第二次请求")
        ])
        await secondLoad.value
        repository.succeedRequest(at: 0, with: [
            makeThread(id: "stale", name: "旧结果", preview: "第一次请求")
        ])
        await firstLoad.value

        XCTAssertEqual(model.filteredThreads.map(\.id), ["newest"])
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
    }

    private func waitForPendingRequests(
        _ repository: DeferredConversationRepositoryStub,
        count: Int
    ) async {
        for _ in 0 ..< 100 where repository.pendingCount < count {
            await Task.yield()
        }
        XCTAssertEqual(repository.pendingCount, count)
    }
}

@MainActor
private final class DemandRepositoryStub: DemandDiscovering {
    var result: Result<[Demand], Error> = .success([])
    private(set) var lastKeyword: String?
    private(set) var lastLatitude: Double?
    private(set) var lastLongitude: Double?
    private(set) var lastDistance: Double?

    func discover(
        page: Int,
        limit: Int,
        keyword: String?,
        lat: Double?,
        lng: Double?,
        distanceKm: Double?
    ) async throws -> [Demand] {
        lastKeyword = keyword
        lastLatitude = lat
        lastLongitude = lng
        lastDistance = distanceKm
        return try result.get()
    }
}

@MainActor
private final class OrderRepositoryStub: OrderListing {
    var result: Result<[Order], Error> = .success([])
    private(set) var lastRole: String?

    func list(role: String?, page: Int) async throws -> [Order] {
        lastRole = role
        return try result.get()
    }
}

@MainActor
private final class ConversationRepositoryStub: ConversationListing {
    var result: Result<[ChatThread], Error> = .success([])
    func conversations() async throws -> [ChatThread] { try result.get() }
}

@MainActor
private final class DeferredConversationRepositoryStub: ConversationListing {
    private var continuations: [CheckedContinuation<[ChatThread], Error>?] = []
    var pendingCount: Int { continuations.count }

    func conversations() async throws -> [ChatThread] {
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func succeedRequest(at index: Int, with threads: [ChatThread]) {
        let continuation = continuations[index]
        continuations[index] = nil
        continuation?.resume(returning: threads)
    }
}

private enum FeatureTestError: LocalizedError {
    case failed
    var errorDescription: String? { "测试失败" }
}

private func makeUser(id: String = "user", name: String = "用户") -> AppUser {
    AppUser(
        id: id,
        name: name,
        avatarUrl: nil,
        coverUrl: nil,
        demandCardCoverUrl: nil,
        creditScore: 60,
        completedOrders: 0,
        goodRate: 0
    )
}

private func makeDemand(id: String) -> Demand {
    Demand(
        id: id,
        title: "需求 \(id)",
        expectedOutcome: "完成",
        minPrice: 100,
        distanceText: "线上",
        countdownText: "1 天",
        applicantCount: 0,
        applicantLimit: 10,
        tags: [],
        state: .normal,
        publisher: makeUser(),
        deadlineText: "明天",
        isCertifiedOnly: false,
        allowNearby: false
    )
}

private func makeOrder(id: String, stage: Order.Stage) -> Order {
    Order(
        id: id,
        demand: makeDemand(id: "demand-\(id)"),
        provider: makeUser(id: "provider"),
        requesterId: "requester",
        providerId: "provider",
        stage: stage,
        rawStatus: stage.title,
        paidAt: nil,
        completedAt: nil,
        submittedAtText: "今天",
        dealAmount: 100,
        escrowAmount: 100,
        remainingPay: 0,
        serviceFee: 0,
        amountHint: ""
    )
}

private func makeThread(
    id: String,
    name: String,
    preview: String,
    unread: Int = 0
) -> ChatThread {
    ChatThread(
        id: id,
        peer: makeUser(id: id, name: name),
        preview: preview,
        timeText: "现在",
        unreadCount: unread,
        relatedDemandTitle: nil,
        isCommunicating: false,
        isSystem: false,
        remainingCommText: nil
    )
}
