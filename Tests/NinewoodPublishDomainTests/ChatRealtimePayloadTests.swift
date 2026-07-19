import Foundation
import XCTest
@testable import NinewoodAPIContracts

final class ChatRealtimePayloadTests: XCTestCase {
    func testParsesPrivateMessageWithNestedSender() {
        let parsed = ChatRealtimePayload.parse([
            "id": "message-1",
            "fromUser": ["id": "sender"],
            "toUser": ["id": "receiver"],
            "content": "你好",
            "createdAt": "2026-07-19T04:00:00.123Z"
        ])

        XCTAssertEqual(parsed?.id, "message-1")
        XCTAssertEqual(parsed?.fromUserId, "sender")
        XCTAssertEqual(parsed?.toUserId, "receiver")
        XCTAssertEqual(parsed?.content, "你好")
        XCTAssertNotNil(parsed?.createdAt)
        XCTAssertFalse(parsed?.hasCardAttachment ?? true)
    }

    func testAcceptsCardOnlyRealtimeMessage() {
        let parsed = ChatRealtimePayload.parse([
            "id": "card-1",
            "fromUserId": "sender",
            "toUserId": "receiver",
            "content": "",
            "cardAttachment": [
                "type": "DEMAND",
                "cardId": "demand-1"
            ]
        ])

        XCTAssertEqual(parsed?.id, "card-1")
        XCTAssertEqual(parsed?.content, "")
        XCTAssertTrue(parsed?.hasCardAttachment ?? false)
    }

    func testRejectsPayloadWithoutSenderOrDisplayableContent() {
        XCTAssertNil(ChatRealtimePayload.parse([
            "toUserId": "receiver",
            "content": "缺少发送者"
        ]))
        XCTAssertNil(ChatRealtimePayload.parse([
            "fromUserId": "sender",
            "toUserId": "receiver",
            "content": "",
            "cardAttachment": NSNull()
        ]))
        XCTAssertNil(ChatRealtimePayload.parse("not-an-object"))
    }

    func testPreservesMergeIdentifier() {
        let parsed = ChatRealtimePayload.parse([
            "fromUserId": "sender",
            "content": "群消息",
            "mergeId": "merge-1"
        ])

        XCTAssertEqual(parsed?.mergeId, "merge-1")
    }

    func testAPIDateAcceptsFractionalAndStandardISO8601() {
        XCTAssertNotNil(APIDate.parse("2026-07-19T04:00:00.123Z"))
        XCTAssertNotNil(APIDate.parse("2026-07-19T04:00:00Z"))
        XCTAssertNil(APIDate.parse(""))
        XCTAssertNil(APIDate.parse("not-a-date"))
    }
}
