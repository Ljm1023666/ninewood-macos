import Foundation

/// Work 模式本地导航意图：不依赖 SSE `navigate` 事件也能立刻离开助手页。
enum AgentNavigateIntent {
    struct Route: Equatable {
        let path: String
        let title: String
    }

    private static let known: [String: Route] = [
        "首页": Route(path: "/", title: "首页"),
        "发现页": Route(path: "/discover", title: "发现"),
        "发现": Route(path: "/discover", title: "发现"),
        "发布": Route(path: "/publish", title: "发布工作台"),
        "发布工作台": Route(path: "/publish", title: "发布工作台"),
        "发布需求": Route(path: "/demands/create", title: "需求卡"),
        "发布需求卡": Route(path: "/demands/create", title: "需求卡"),
        "需求卡": Route(path: "/demands/create", title: "需求卡"),
        "发布服务卡": Route(path: "/service-cards/create", title: "服务卡"),
        "服务卡": Route(path: "/service-cards/create", title: "服务卡"),
        "订单": Route(path: "/orders", title: "订单"),
        "消息": Route(path: "/messages", title: "消息"),
        "卡池": Route(path: "/card-pool", title: "卡池"),
        "认证中心": Route(path: "/cert-center", title: "认证中心"),
        "认证": Route(path: "/cert-center", title: "认证中心"),
        "圈子": Route(path: "/circles", title: "圈子"),
        "自然回": Route(path: "/loops/discover", title: "回"),
        "回": Route(path: "/loops/discover", title: "回"),
        "发现回": Route(path: "/loops/discover", title: "发现回"),
        "我的回": Route(path: "/loops/mine", title: "我的回"),
        "找人": Route(path: "/search", title: "找人"),
        "个人主页": Route(path: "/profile", title: "个人主页"),
        "我的": Route(path: "/profile", title: "个人主页"),
        "AI助手": Route(path: "/agent", title: "AI 助手"),
    ]

    private static let aliases: [String: String] = [
        "发人": "找人",
        "搜人": "找人",
        "搜索用户": "找人",
        "找人页": "找人",
        "发需求": "发布需求",
        "发服务卡": "发布服务卡",
        "发布服务": "发布服务卡",
        "个人中心": "个人主页",
        "主页": "首页",
        "页面中心": "首页",
    ]

    /// 匹配「打开/跳转/去/前往 …」类整句导航；否则返回 nil。
    static func resolve(message: String) -> Route? {
        let compact = message.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        guard let target = extractTarget(compact) else { return nil }
        return resolveTarget(target)
    }

    private static func extractTarget(_ compact: String) -> String? {
        // (?:帮我)?(?:打开|跳转(?:到)?|去|前往)(?:一下)?(.+?)(?:页面|界面|页)?$
        let pattern = "^(?:帮我)?(?:打开|跳转到|跳转|去|前往)(?:一下)?(.+?)(?:页面|界面|页)?$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: compact)
        else {
            return nil
        }
        return normalize(String(compact[range]))
    }

    private static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripChars = CharacterSet(charactersIn: "「」『』【】[]()（）?？!！")
        s = s.components(separatedBy: stripChars).joined()
        if s.hasSuffix("页面") { s = String(s.dropLast(2)) }
        else if s.hasSuffix("界面") { s = String(s.dropLast(2)) }
        else if s.hasSuffix("模块") { s = String(s.dropLast(2)) }
        else if s.hasSuffix("功能") { s = String(s.dropLast(2)) }
        return s
    }

    private static func resolveTarget(_ raw: String) -> Route? {
        let key = normalize(raw)
        guard !key.isEmpty else { return nil }
        if let route = known[key] { return route }
        if let alias = aliases[key], let route = known[alias] { return route }
        for (alias, target) in aliases {
            if key.contains(alias) || alias.contains(key), let route = known[target] {
                return route
            }
        }
        for (name, route) in known {
            if key.contains(name) || name.contains(key) {
                return route
            }
        }
        return nil
    }
}
