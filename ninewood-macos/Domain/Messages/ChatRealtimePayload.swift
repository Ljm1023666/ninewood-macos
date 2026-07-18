import Foundation

/// Socket.IO `private:message` / `merge:message` 载荷解析（与 UI 解耦）。
enum ChatRealtimePayload {
    struct Parsed: Equatable {
        let id: String
        let fromUserId: String
        let toUserId: String
        let content: String
        let createdAt: Date
        let hasCardAttachment: Bool
        let mergeId: String?
    }

    static func parse(_ raw: Any) -> Parsed? {
        let dict: [String: Any]
        if let d = raw as? [String: Any] {
            dict = d
        } else if let d = raw as? NSDictionary {
            dict = d as? [String: Any] ?? [:]
        } else {
            return nil
        }

        let from = string(dict, keys: ["fromUserId", "senderId"])
            ?? nestedString(dict, path: ["fromUser", "id"])
            ?? ""
        let to = string(dict, keys: ["toUserId", "receiverId"])
            ?? nestedString(dict, path: ["toUser", "id"])
            ?? ""
        let content = (dict["content"] as? String) ?? ""
        guard !from.isEmpty, !content.isEmpty else { return nil }

        let id = (dict["id"] as? String) ?? UUID().uuidString
        let createdAt: Date
        if let iso = dict["createdAt"] as? String, let parsed = APIDate.parse(iso) {
            createdAt = parsed
        } else {
            createdAt = Date()
        }

        return Parsed(
            id: id,
            fromUserId: from,
            toUserId: to,
            content: content,
            createdAt: createdAt,
            hasCardAttachment: hasCardAttachment(dict),
            mergeId: dict["mergeId"] as? String
        )
    }

    private static func hasCardAttachment(_ dict: [String: Any]) -> Bool {
        if dict["cardAttachment"] != nil { return true }
        if let nested = dict["cardAttachment"] as? [String: Any], !nested.isEmpty { return true }
        if dict["card_attachment"] != nil { return true }
        return false
    }

    private static func string(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func nestedString(_ dict: [String: Any], path: [String]) -> String? {
        var current: Any = dict
        for segment in path {
            guard let next = (current as? [String: Any])?[segment] else { return nil }
            current = next
        }
        return current as? String
    }
}
