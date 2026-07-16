import SwiftUI
import AppKit

enum AppTheme {
    /// DESIGN.md accent `#007AFF` — 保留主色，表面走中性
    static let primary = Color(red: 0 / 255, green: 122 / 255, blue: 255 / 255)
    static let accentHover = Color(red: 10 / 255, green: 132 / 255, blue: 255 / 255)

    static let groupedBackground = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let surfaceLow = Color(nsColor: .underPageBackgroundColor)
    static let onSurface = Color.primary
    static let secondaryLabel = Color.secondary
    static let fill = Color(nsColor: .separatorColor).opacity(0.35)
    static let outlineVariant = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.14)

    /// 选中态浅底（仅用于列表选中 / 焦点块）
    static let softPrimary = primary.opacity(0.10)
    static let softTeal = Color(red: 0 / 255, green: 106 / 255, blue: 104 / 255).opacity(0.10)

    /// 状态色：只用于状态位，不用于价格/装饰
    static let urgent = Color(red: 255 / 255, green: 153 / 255, blue: 0 / 255)
    static let countdownBackground = Color(red: 1, green: 244 / 255, blue: 229 / 255)
    static let countdownForeground = Color(red: 230 / 255, green: 81 / 255, blue: 0 / 255)
    static let openStatus = Color(red: 0 / 255, green: 204 / 255, blue: 102 / 255)
    static let error = Color(red: 255 / 255, green: 51 / 255, blue: 51 / 255)
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
    static let sidebarWidth: CGFloat = 200
    static let documentMaxWidth: CGFloat = 640
    static let documentWideMaxWidth: CGFloat = 720

    /// 兼容旧调用：已改为平坦表面，避免工作台「氛围渐变」
    @available(*, deprecated, message: "Use workspaceBackground or documentBackground")
    static var canvasGradient: Color { workspaceBackground }
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
