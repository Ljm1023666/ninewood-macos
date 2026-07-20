import SwiftUI

/// 回中心路径解析（对齐 Windows `/loops/*`）。
enum LoopHubRoute: Equatable {
    case discover
    case mine
    case accept
    case offering(id: String)
    case run(id: String)

    static func parse(_ path: String) -> LoopHubRoute {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.first == "loops" else { return .discover }
        if parts.count >= 3 {
            switch parts[1] {
            case "offerings": return .offering(id: parts[2])
            case "runs": return .run(id: parts[2])
            default: break
            }
        }
        if parts.count >= 2 {
            switch parts[1] {
            case "mine": return .mine
            case "accept": return .accept
            case "discover": return .discover
            default: break
            }
        }
        return .discover
    }

    var showsHubTabs: Bool {
        switch self {
        case .discover, .mine, .accept, .run: true
        case .offering: true
        }
    }

    var tabKey: LoopHubTab {
        switch self {
        case .accept: .accept
        case .mine, .run: .mine
        case .discover, .offering: .discover
        }
    }
}

enum LoopHubTab: String, CaseIterable, Identifiable {
    case discover
    case mine
    case accept

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discover: "发现回"
        case .mine: "我的回"
        case .accept: "承接人回"
        }
    }

    var systemImage: String {
        switch self {
        case .discover: "safari"
        case .mine: "arrow.triangle.2.circlepath"
        case .accept: "person.2"
        }
    }

    var path: String {
        switch self {
        case .discover: "/loops/discover"
        case .mine: "/loops/mine"
        case .accept: "/loops/accept"
        }
    }
}

enum LoopHubFormatting {
    static func duration(_ ms: Double?) -> String {
        guard let ms else { return "待运行后估算" }
        if ms < 60_000 { return "\(max(1, Int((ms / 1000).rounded()))) 秒" }
        return "\(max(1, Int((ms / 60_000).rounded()))) 分钟"
    }

    static func publicRate(_ value: Double?) -> String {
        guard let value else { return "验证适配中" }
        return "\(Int((value * 100).rounded()))%"
    }

    static func kindLabel(_ raw: String) -> String {
        switch raw.uppercased() {
        case "HUMAN": return "人回"
        case "EARTH": return "地回"
        case "HEAVEN": return "天回"
        default: return raw
        }
    }

    static func kindTint(_ raw: String) -> Color {
        switch raw.uppercased() {
        case "HUMAN": return AppTheme.human
        case "EARTH": return AppTheme.secondary
        case "HEAVEN": return AppTheme.primary
        default: return AppTheme.outlineVariant
        }
    }

    static func statusLabel(_ raw: String) -> String {
        switch raw.uppercased() {
        case "TRIGGERED": return "已触发"
        case "MATCHING": return "匹配中"
        case "EXECUTING": return "运行中"
        case "WAITING_HUMAN": return "等待你处理"
        case "VERIFYING": return "核验中"
        case "SUCCEEDED": return "已成功"
        case "FAILED": return "失败"
        case "INCONCLUSIVE": return "待确认"
        case "COMPENSATING": return "补偿中"
        case "CLOSED": return "已结束"
        default: return raw
        }
    }

    static func prettyJSON(_ value: LoopJSONValue?) -> String {
        guard let value else { return "null" }
        return pretty(value)
    }

    private static func pretty(_ value: LoopJSONValue, indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        switch value {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return String(n)
        case .string(let s): return "\"\(s)\""
        case .array(let arr):
            if arr.isEmpty { return "[]" }
            let body = arr.map { "\(pad)  \(pretty($0, indent: indent + 1))" }.joined(separator: ",\n")
            return "[\n\(body)\n\(pad)]"
        case .object(let obj):
            if obj.isEmpty { return "{}" }
            let body = obj.keys.sorted().map { key in
                "\(pad)  \"\(key)\": \(pretty(obj[key]!, indent: indent + 1))"
            }.joined(separator: ",\n")
            return "{\n\(body)\n\(pad)}"
        }
    }
}

/// 回中心壳：顶栏三 Tab + 子路由内容。
struct LoopHubView: View {
    @Environment(AppSession.self) private var session
    var frontendPreview: Bool = false

    var body: some View {
        let path = session.navigation.currentPath
        let route = LoopHubRoute.parse(path)
        VStack(spacing: 0) {
            if route.showsHubTabs {
                LoopHubNavBar(active: route.tabKey)
            }
            Group {
                switch route {
                case .discover:
                    LoopDiscoverView(frontendPreview: frontendPreview)
                case .mine:
                    LoopMineView(frontendPreview: frontendPreview)
                case .accept:
                    LoopAcceptPlaceholderView()
                case .offering(let id):
                    LoopOfferingDetailView(offeringID: id, frontendPreview: frontendPreview)
                case .run(let id):
                    LoopRunDetailView(runID: id, frontendPreview: frontendPreview)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.documentBackground)
        .accessibilityIdentifier("loop-hub")
    }
}

private struct LoopHubNavBar: View {
    @Environment(AppSession.self) private var session
    let active: LoopHubTab

    var body: some View {
        HStack(spacing: 8) {
            ForEach(LoopHubTab.allCases) { tab in
                Button {
                    _ = session.navigation.navigate(to: tab.path)
                } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            active == tab ? AppTheme.softPrimary : AppTheme.fill.opacity(0.35),
                            in: Capsule()
                        )
                        .foregroundStyle(active == tab ? AppTheme.primary : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(active == tab ? .isSelected : [])
                .accessibilityIdentifier("loop-hub-tab-\(tab.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AppTheme.surface.opacity(0.92))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
