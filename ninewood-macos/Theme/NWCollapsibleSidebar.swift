import SwiftUI

/// 可收纳侧栏：宽度动画 + 折叠窄轨。
/// 折叠态不要再放与聊天顶栏重复的同一枚按钮。
struct NWCollapsibleSidebar<Expanded: View, Collapsed: View>: View {
    var isExpanded: Bool
    var expandedWidth: CGFloat = 280
    var collapsedWidth: CGFloat = 52
    var showsDivider: Bool = true
    @ViewBuilder var expanded: () -> Expanded
    @ViewBuilder var collapsed: () -> Collapsed

    private var width: CGFloat { isExpanded ? expandedWidth : collapsedWidth }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if isExpanded {
                    expanded()
                        .frame(width: expandedWidth, alignment: .topLeading)
                } else {
                    collapsed()
                        .frame(width: collapsedWidth, alignment: .top)
                }
            }
            .frame(width: width, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()
            .background(AppTheme.workspaceBackground)

            if showsDivider {
                Divider()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }
}

/// 业务侧栏开关：禁止再用 `sidebar.*`，以免与系统主导航按钮撞脸。
struct NWPanelToggleButton: View {
    enum Role {
        case conversations
        case profileMenu

        var symbol: String {
            switch self {
            case .conversations: "list.bullet"
            case .profileMenu: "person.crop.circle"
            }
        }

        func help(isExpanded: Bool) -> String {
            switch self {
            case .conversations:
                isExpanded ? "收起对话列表" : "展开对话列表"
            case .profileMenu:
                isExpanded ? "收起我的菜单" : "展开我的菜单"
            }
        }
    }

    var role: Role
    var isExpanded: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: role.symbol)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(role.help(isExpanded: isExpanded))
    }
}
