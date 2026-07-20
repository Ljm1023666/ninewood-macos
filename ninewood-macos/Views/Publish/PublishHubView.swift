import SwiftUI

/// 发布工作台入口：先选需求卡 / 服务卡，再进入独立工作区。
struct PublishHubView: View {
    @Environment(AppSession.self) private var session
    var frontendPreview: Bool = false

    @State private var mode: PublishCardMode = .demand

    private enum PublishCardMode: String, CaseIterable, Identifiable {
        case demand
        case service
        var id: String { rawValue }

        var title: String {
            switch self {
            case .demand: "发布需求卡"
            case .service: "发布服务卡"
            }
        }

        var subtitle: String {
            switch self {
            case .demand: "让服务者找到我"
            case .service: "展示我能提供的服务"
            }
        }

        var detail: String {
            switch self {
            case .demand:
                "说清楚要解决的问题、预算、线上/线下与期望结果，让合适的服务者主动来找你。"
            case .service:
                "整理服务标题、简介、交付方式、报价区间与能力声明，让有明确需求的人找到你。"
            }
        }

        var systemImage: String {
            switch self {
            case .demand: "doc.text"
            case .service: "briefcase"
            }
        }

        var path: String {
            switch self {
            case .demand: "/demands/create"
            case .service: "/service-cards/create"
            }
        }

        var focusPoints: [String] {
            switch self {
            case .demand:
                ["问题描述与目标", "分类与预算", "线上 / 线下与地区", "发布前结构化确认"]
            case .service:
                ["服务范围与交付结果", "交付方式与报价", "类别与能力声明", "发布前结构化确认"]
            }
        }
    }

    var body: some View {
        DocumentShell(maxWidth: 980) {
            VStack(alignment: .leading, spacing: AppTheme.space24) {
                header
                HStack(alignment: .top, spacing: AppTheme.space24) {
                    choiceColumn
                        .frame(maxWidth: .infinity, alignment: .leading)
                    confirmPanel
                        .frame(width: 320)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("发布工作台")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(AppTheme.onSurface)
            Text("先决定，你要让谁找到你")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.onSurface)
            Text("需求卡用于寻找服务者，服务卡用于展示能力。下一步由 AI 在专用工作区整理字段；最终确认与提交不在九木助手聊天里完成。")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var choiceColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择发布方向")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(PublishCardMode.allCases) { item in
                Button {
                    mode = item
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(mode == item ? AppTheme.primary : .secondary)
                            .frame(width: 36, height: 36)
                            .background(
                                (mode == item ? AppTheme.softPrimary : AppTheme.fill.opacity(0.35)),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.title)
                                    .font(.headline)
                                Spacer()
                                if mode == item {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppTheme.primary)
                                }
                            }
                            Text(item.subtitle)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppTheme.primary.opacity(0.9))
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(mode == item ? AppTheme.primary : AppTheme.outlineVariant, lineWidth: mode == item ? 1.5 : 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityIdentifier(item == .demand ? "publish-hub-choose-demand" : "publish-hub-choose-service")
                .accessibilityAddTraits(mode == item ? .isSelected : [])
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("本页会帮你整理")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(mode.focusPoints, id: \.self) { point in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(AppTheme.primary)
                            Text(point)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(AppTheme.fill.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private var confirmPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode == .demand ? "DEMAND CARD" : "SERVICE CARD")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(0.6)

            Text(mode == .demand ? "让合适的服务者找到你" : "让有需求的人找到你")
                .font(.title2.bold())
                .foregroundStyle(AppTheme.onSurface)

            Text(mode.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                stepRow(1, "选择卡片类型", active: true)
                stepRow(2, "用 AI 整理成结构化字段", active: false)
                stepRow(3, "核对预览后确认发布", active: false)
            }
            .padding(.vertical, 4)

            Spacer(minLength: 12)

            Button {
                openWorkspace()
            } label: {
                Label("开始用 AI 整理", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel("开始用 AI 整理")
            .accessibilityIdentifier("publish-hub-start-ai")
            .accessibilityHint("进入 AI 整理工作区")
            .help("开始用 AI 整理")

            Text("AI 只负责整理草稿；最终确认与提交在专用工作区完成。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant)
        }
    }

    private func stepRow(_ index: Int, _ text: String, active: Bool) -> some View {
        HStack(spacing: 10) {
            Text(String(format: "%02d", index))
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(active ? AppTheme.primary : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    (active ? AppTheme.softPrimary : AppTheme.fill.opacity(0.3)),
                    in: Circle()
                )
            Text(text)
                .font(.caption)
                .foregroundStyle(active ? AppTheme.onSurface : .secondary)
        }
    }

    private func openWorkspace() {
        if frontendPreview {
            _ = session.navigation.navigate(to: mode.path)
            return
        }
        _ = session.navigation.navigate(to: mode.path)
    }
}
