import Foundation

struct AgentNavigationEvent: Equatable {
    let path: String
    let title: String?

    static func decode(event: String, data: String) -> AgentNavigationEvent? {
        guard event.lowercased().replacingOccurrences(of: "-", with: "_") == "tool_result",
              let payload = data.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              object["name"] as? String == "navigate_to",
              object["success"] as? Bool == true,
              let result = object["data"] as? [String: Any],
              let path = result["path"] as? String,
              path.hasPrefix("/")
        else {
            return nil
        }
        return AgentNavigationEvent(path: path, title: result["title"] as? String)
    }
}

struct AgentPendingToolEvent: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let message: String
    let argumentsSummary: String

    static func decode(event: String, data: String) -> AgentPendingToolEvent? {
        let normalized = event.lowercased().replacingOccurrences(of: "-", with: "_")
        guard normalized == "tool_pending",
              let payload = data.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let id = object["id"] as? String,
              let name = object["name"] as? String
        else {
            return nil
        }
        let message = (object["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "助手请求执行「\(name)」"
        let args = object["arguments"] as? [String: Any] ?? [:]
        return AgentPendingToolEvent(
            id: id,
            name: name,
            message: message.isEmpty ? "助手请求执行「\(name)」" : message,
            argumentsSummary: summarizeArguments(args)
        )
    }

    private static func summarizeArguments(_ args: [String: Any]) -> String {
        guard !args.isEmpty else { return "（无参数）" }
        let preferred = ["title", "demandId", "orderId", "applicantId", "content", "description", "path"]
        var lines: [String] = []
        for key in preferred {
            if let value = args[key] {
                lines.append("\(key): \(stringify(value))")
            }
        }
        if lines.isEmpty {
            for (key, value) in args.sorted(by: { $0.key < $1.key }).prefix(6) {
                lines.append("\(key): \(stringify(value))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func stringify(_ value: Any) -> String {
        switch value {
        case let s as String:
            return s.count > 120 ? String(s.prefix(117)) + "…" : s
        case let n as NSNumber:
            return n.stringValue
        case let b as Bool:
            return b ? "true" : "false"
        default:
            if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
               let text = String(data: data, encoding: .utf8) {
                return text.count > 120 ? String(text.prefix(117)) + "…" : text
            }
            return String(describing: value)
        }
    }
}
