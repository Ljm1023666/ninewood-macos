import XCTest
@testable import NinewoodOrderDomain

final class OrderActionPolicyTests: XCTestCase {
    func testRequesterCanPrepayAndCancelBeforePrepayment() {
        let policy = OrderActionPolicy(
            role: .requester,
            lifecycle: .inProgress,
            isPrepaid: false
        )

        XCTAssertEqual(
            policy.allowedActions,
            [.prepayServiceFee, .cancel, .refresh]
        )
    }

    func testProviderCanCompleteOnlyAfterPrepayment() {
        let waiting = OrderActionPolicy(
            role: .provider,
            lifecycle: .inProgress,
            isPrepaid: false
        )
        let paid = OrderActionPolicy(
            role: .provider,
            lifecycle: .inProgress,
            isPrepaid: true
        )

        XCTAssertEqual(waiting.allowedActions, [.refresh])
        XCTAssertEqual(paid.allowedActions, [.markComplete, .completePartially, .refresh])
    }

    func testRequesterCanSettleOrDisputeWaitingReview() {
        let policy = OrderActionPolicy(
            role: .requester,
            lifecycle: .waitingReview,
            isPrepaid: true
        )

        XCTAssertEqual(policy.allowedActions, [.confirmAndSettle, .dispute, .refresh])
    }

    func testCancelledOrderHasNoConsequentialActions() {
        let policy = OrderActionPolicy(
            role: .requester,
            lifecycle: .cancelled,
            isPrepaid: true
        )

        XCTAssertEqual(policy.allowedActions, [.refresh])
    }

    func testDisputedAndRefundedHaveNoReview() {
        let disputed = OrderActionPolicy(role: .requester, lifecycle: .disputed, isPrepaid: true)
        let cancelled = OrderActionPolicy(role: .provider, lifecycle: .cancelled, isPrepaid: false)
        XCTAssertEqual(disputed.allowedActions, [.refresh])
        XCTAssertEqual(cancelled.allowedActions, [.refresh])
    }

    func testAcceptedRequesterMayCancelOnly() {
        let policy = OrderActionPolicy(role: .requester, lifecycle: .accepted, isPrepaid: false)
        XCTAssertEqual(policy.allowedActions, [.cancel, .refresh])
    }

    func testCompletedAllowsReview() {
        let policy = OrderActionPolicy(role: .requester, lifecycle: .completed, isPrepaid: true)
        XCTAssertEqual(policy.allowedActions, [.review, .refresh])
    }

    func testPaymentGateRequiresBreakdown() {
        XCTAssertFalse(
            OrderPaymentGate.canConfirmPrepay(
                breakdownLoaded: false,
                loadFailed: false,
                payableNow: 10,
                alreadyPrepaid: false
            )
        )
        XCTAssertFalse(
            OrderPaymentGate.canConfirmPrepay(
                breakdownLoaded: true,
                loadFailed: true,
                payableNow: 10,
                alreadyPrepaid: false
            )
        )
        XCTAssertFalse(
            OrderPaymentGate.canConfirmPrepay(
                breakdownLoaded: true,
                loadFailed: false,
                payableNow: 0,
                alreadyPrepaid: false
            )
        )
        XCTAssertTrue(
            OrderPaymentGate.canConfirmPrepay(
                breakdownLoaded: true,
                loadFailed: false,
                payableNow: 5,
                alreadyPrepaid: false
            )
        )
        XCTAssertFalse(
            OrderPaymentGate.canConfirmPrepay(
                breakdownLoaded: true,
                loadFailed: false,
                payableNow: 5,
                alreadyPrepaid: true
            )
        )
    }
}
