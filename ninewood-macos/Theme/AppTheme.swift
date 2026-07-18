import SwiftUI
import AppKit

enum AppTheme {
    /// 九木标识蓝 `#2FBBE0`；表面仍保持中性，避免品牌色侵入业务状态。
    static let primary = Color(red: 47 / 255, green: 187 / 255, blue: 224 / 255)
    static let accentHover = Color(red: 31 / 255, green: 169 / 255, blue: 207 / 255)

    /// 自适应表面：跟随系统浅色 / 深色，避免「白底 + 浅字」或「深底 + 深字」
    static let groupedBackground = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .textBackgroundColor)
    static let surfaceLow = Color(nsColor: .controlBackgroundColor)
    static let onSurface = Color.primary
    static let secondaryLabel = Color.secondary
    static let fill = Color(nsColor: .separatorColor).opacity(0.35)
    static let outlineVariant = Color(nsColor: .separatorColor)

    /// 对方消息气泡（相对 surface 略抬升，深浅色都可读）
    static let bubbleIncoming = nwAdaptive(
        light: NSColor(red: 245 / 255, green: 247 / 255, blue: 248 / 255, alpha: 1),
        dark: NSColor(red: 0.22, green: 0.22, blue: 0.24, alpha: 1)
    )

    /// 选中态浅底（仅用于列表选中 / 焦点块）
    static let softPrimary = primary.opacity(0.16)
    static let softTeal = Color(red: 0 / 255, green: 106 / 255, blue: 104 / 255).opacity(0.16)

    /// 状态色：只用于状态位，不用于价格/装饰
    static let urgent = Color(red: 255 / 255, green: 153 / 255, blue: 0 / 255)
    static let countdownBackground = nwAdaptive(
        light: NSColor(red: 1, green: 244 / 255, blue: 229 / 255, alpha: 1),
        dark: NSColor(red: 0.35, green: 0.22, blue: 0.08, alpha: 1)
    )
    static let countdownForeground = nwAdaptive(
        light: NSColor(red: 230 / 255, green: 81 / 255, blue: 0 / 255, alpha: 1),
        dark: NSColor(red: 1, green: 0.72, blue: 0.35, alpha: 1)
    )
    static let openStatus = Color(red: 66 / 255, green: 207 / 255, blue: 165 / 255)
    static let error = Color(red: 214 / 255, green: 40 / 255, blue: 40 / 255)
    static let secondary = Color(red: 0 / 255, green: 106 / 255, blue: 104 / 255)
    static let human = Color(red: 176 / 255, green: 88 / 255, blue: 0 / 255)
    static let background = groupedBackground

    /// Workspace 列表/详情平坦表面（无装饰渐变）
    static let workspaceBackground = Color(nsColor: .controlBackgroundColor)
    /// Document 表单/设置外侧底
    static let documentBackground = Color(nsColor: .windowBackgroundColor)

    // MARK: - Spacing (8 的倍数)

    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space24: CGFloat = 24

    static let horizontalPadding: CGFloat = space24
    static let cardRadius: CGFloat = 10
    static let buttonRadius: CGFloat = 8
    static let sidebarWidth: CGFloat = 240
    static let listPaneWidth: CGFloat = 420
    static let documentMaxWidth: CGFloat = 640
    static let documentWideMaxWidth: CGFloat = 720

    /// 兼容旧调用：已改为平坦表面，避免工作台「氛围渐变」
    @available(*, deprecated, message: "Use workspaceBackground or documentBackground")
    static var canvasGradient: Color { workspaceBackground }

    /// 浅色 / 深色成对色
    static func nwAdaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }))
    }
}

extension View {
    /// 可交互分区容器：描边、无阴影
    func ninewoodCard() -> some View {
        self
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
            }
    }

    /// 兼容从 iOS 移植的调用名
    func jiumuCard() -> some View {
        ninewoodCard()
    }

    /// 分栏左栏必须顶对齐，否则空状态时整列会被 HStack 居中下沉
    func paneColumn(minWidth: CGFloat, idealWidth: CGFloat) -> some View {
        self
            .frame(minWidth: minWidth, idealWidth: idealWidth, maxWidth: idealWidth + 80)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(AppTheme.workspaceBackground)
    }

    /// 详情 pane 切换 identity 时不触发动画，避免列表点击抖动
    func nwStableDetailIdentity<ID: Hashable>(_ id: ID) -> some View {
        self.id(id).transaction { $0.animation = nil }
    }

    /// 列表选中：浅蓝底 + 左侧 3px 品牌条（对齐 ui-renderings）
    func nwSelectionChrome(isSelected: Bool, cornerRadius: CGFloat = 8) -> some View {
        background(
            isSelected ? AppTheme.softPrimary : Color.clear,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(AppTheme.primary)
                    .frame(width: 3)
            }
        }
    }
}

// MARK: - Shared chrome

/// 顶对齐空状态（替代会垂直居中的 ContentUnavailableView）
struct NWEmptyState: View {
    let title: String
    var systemImage: String = "tray"
    var message: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.space12) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(title)
                .font(.headline)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.space16)
    }
}

struct NWDetailPlaceholder: View {
    let title: String
    var systemImage: String = "doc.text"
    var message: String? = nil

    var body: some View {
        VStack(spacing: AppTheme.space12) {
            Image(systemName: systemImage)
                .font(.title.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.workspaceBackground)
    }
}

/// 窗格辅助说明（不含与 navigationTitle 重复的大标题）
struct NWPaneCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.space16)
            .padding(.top, AppTheme.space12)
            .padding(.bottom, AppTheme.space8)
    }
}

/// 兼容旧调用：仅保留副标题，避免与工具栏标题重复
struct NWPaneHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.space16)
        .padding(.top, AppTheme.space12)
        .padding(.bottom, AppTheme.space8)
        .accessibilityLabel(title)
    }
}

struct NWSearchBar: View {
    @Binding var text: String
    var placeholder: String
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: AppTheme.space8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .onSubmit { onSubmit?() }
        }
        .padding(.horizontal, AppTheme.space12)
        .padding(.vertical, AppTheme.space8)
        .background(AppTheme.fill.opacity(0.55), in: RoundedRectangle(cornerRadius: AppTheme.buttonRadius, style: .continuous))
    }
}

struct NWStatusChip: View {
    let text: String
    var tint: Color = AppTheme.primary

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, AppTheme.space8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

/// 主操作按钮：实心 #2FBBE0，高度约 40–42pt
struct NWPrimaryCTA: View {
    let title: String
    var systemImage: String? = nil
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: AppTheme.buttonRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// 横向筛选 pill（全部 / 角色 / 状态）
struct NWFilterPills<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.self) { item in
                let selected = selection == item
                Button {
                    selection = item
                } label: {
                    Text(title(item))
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? .white : AppTheme.secondaryLabel)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            selected ? AppTheme.primary : AppTheme.fill.opacity(0.35),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}
