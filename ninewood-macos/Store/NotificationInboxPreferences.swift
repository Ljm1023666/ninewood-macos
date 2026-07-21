import Foundation

/// 站内通知收件箱的本地分类偏好（拉取展示过滤；不等于系统推送通道）。
enum NotificationInboxCategory: String, CaseIterable, Identifiable {
    case order
    case demand
    case message
    case welfare
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .order: "订单"
        case .demand: "需求"
        case .message: "消息"
        case .welfare: "福利"
        case .system: "系统"
        }
    }

    static func from(notificationType type: String?) -> NotificationInboxCategory {
        let normalized = (type ?? "").uppercased()
        if normalized.contains("ORDER") { return .order }
        if normalized.contains("DEMAND") || normalized.contains("BID") || normalized.contains("REQUEST") {
            return .demand
        }
        if normalized.contains("MESSAGE") || normalized.contains("CHAT") { return .message }
        if normalized.contains("WELFARE") { return .welfare }
        return .system
    }
}

enum NotificationInboxPreferences {
    private static let defaultsKey = "ninewood.notificationInbox.enabledCategories"

    /// 收件箱默认全开：这是用户主动打开的列表，不是被动推送。
    static var enabledRawValues: Set<String> {
        get {
            if let stored = UserDefaults.standard.array(forKey: defaultsKey) as? [String] {
                return Set(stored)
            }
            return Set(NotificationInboxCategory.allCases.map(\.rawValue))
        }
        set {
            UserDefaults.standard.set(Array(newValue).sorted(), forKey: defaultsKey)
        }
    }

    static func isEnabled(_ category: NotificationInboxCategory) -> Bool {
        enabledRawValues.contains(category.rawValue)
    }

    static func setEnabled(_ category: NotificationInboxCategory, _ enabled: Bool) {
        var next = enabledRawValues
        if enabled {
            next.insert(category.rawValue)
        } else {
            next.remove(category.rawValue)
        }
        enabledRawValues = next
    }

    static func isEnabled(forNotificationType type: String?) -> Bool {
        isEnabled(NotificationInboxCategory.from(notificationType: type))
    }
}
