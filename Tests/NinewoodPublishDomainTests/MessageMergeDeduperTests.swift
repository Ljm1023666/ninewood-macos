import Foundation
@testable import NinewoodAPIContracts
import XCTest

final class MessageMergeDeduperTests: XCTestCase {
    func testDedupesSenderFanOutCopies() throws {
        let messages = [
            try message(id: "1", from: "me", to: "b", content: "hello", at: "2026-07-18T10:00:00.000Z"),
            try message(id: "2", from: "me", to: "c", content: "hello", at: "2026-07-18T10:00:00.000Z"),
            try message(id: "3", from: "b", to: "me", content: "reply", at: "2026-07-18T10:01:00.000Z")
        ]

        let timeline = MessageMergeDeduper.timeline(messages, viewerID: "me")

        XCTAssertEqual(timeline.count, 2)
        XCTAssertEqual(timeline.map(\.id), ["1", "3"])
    }

    func testKeepsIncomingMessagesAddressedToViewer() throws {
        let messages = [
            try message(id: "1", from: "a", to: "me", content: "ping", at: "2026-07-18T10:00:00.000Z"),
            try message(id: "2", from: "a", to: "other", content: "hidden", at: "2026-07-18T10:00:01.000Z")
        ]

        let timeline = MessageMergeDeduper.timeline(messages, viewerID: "me")

        XCTAssertEqual(timeline.map(\.id), ["1"])
    }

    private func message(
        id: String,
        from: String,
        to: String,
        content: String,
        at: String
    ) throws -> MessageDTO {
        let json = """
        {
          "id": "\(id)",
          "fromUserId": "\(from)",
          "toUserId": "\(to)",
          "content": "\(content)",
          "createdAt": "\(at)"
        }
        """
        return try JSONDecoder().decode(MessageDTO.self, from: Data(json.utf8))
    }
}
