import SwiftUI

struct DiscoverView: View {
    @State private var model: DiscoverFeatureModel
    @State private var searchText = ""
    @State private var showNearbyOnly = false
    private let usesDesignFixtures: Bool

    init(repository: DemandRepository) {
        _model = State(initialValue: DiscoverFeatureModel(repository: repository))
        usesDesignFixtures = false
    }

    init(previewDemands: [Demand]) {
        _model = State(initialValue: DiscoverFeatureModel(previewDemands: previewDemands))
        usesDesignFixtures = true
    }

    private var isDesignPreview: Bool {
        usesDesignFixtures
            || ProcessInfo.processInfo.environment["NINEWOOD_DESIGN_PREVIEW"] == "03-discover"
            || ProcessInfo.processInfo.environment["NINEWOOD_DESIGN_PREVIEW"] == "discover"
            || CommandLine.arguments.contains("--discover-design-preview")
            || CommandLine.arguments.contains("--03-discover-design-preview")
    }

    var body: some View {
        SplitListDetailShell(
            minListWidth: 300,
            idealListWidth: AppTheme.listPaneWidth
        ) {
            listPane
        } detail: {
            Group {
                if let selectedDemand = model.selectedDemand {
                    DemandDetailView(
                        demand: selectedDemand,
                        previewMode: isDesignPreview
                    )
                    .nwStableDetailIdentity(selectedDemand.id)
                } else {
                    NWDetailPlaceholder(
                        title: "选择需求",
                        systemImage: "doc.text.magnifyingglass",
                        message: "从左侧列表选择一条需求查看详情"
                    )
                }
            }
        }
        .task { await model.load() }
        .navigationTitle("发现")
    }

    // MARK: - List (`03-discover` middle pane)

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text("附近需求")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.onSurface)
                Spacer(minLength: 0)
                Button {
                    showNearbyOnly.toggle()
                    if !isDesignPreview {
                        Task {
                            await model.load(
                                keyword: searchText,
                                nearbyOnly: showNearbyOnly
                            )
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 12, weight: .semibold))
                        Text(showNearbyOnly ? "仅附近" : "附近")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(showNearbyOnly ? AppTheme.primary : AppTheme.secondaryLabel)
                    .help(showNearbyOnly ? "已开启：只看允许附近发现的需求" : "点击后只看允许附近发现的需求")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            DiscoverSearchBar(text: $searchText) {
                if isDesignPreview { return }
                Task {
                    await model.load(keyword: searchText, nearbyOnly: showNearbyOnly)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            if let loadError = model.errorMessage {
                VStack(alignment: .leading, spacing: AppTheme.space8) {
                    Text(loadError)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("重新加载") {
                        Task {
                            await model.load(keyword: searchText, nearbyOnly: showNearbyOnly)
                        }
                    }
                }
                .padding(16)
                Spacer(minLength: 0)
            } else if displayDemands.isEmpty && !model.isLoading {
                NWEmptyState(title: "暂无需求", systemImage: "tray", message: "稍后再来看看附近有什么新需求")
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(displayDemands) { demand in
                            let selected = model.selectedDemand?.id == demand.id
                            Button {
                                model.selectedDemand = demand
                            } label: {
                                DemandRowView(demand: demand, isSelected: selected)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(selected ? AppTheme.softPrimary : Color.clear)
                                    .overlay(alignment: .leading) {
                                        if selected {
                                            Rectangle()
                                                .fill(AppTheme.primary)
                                                .frame(width: 3)
                                        }
                                    }
                                    .overlay {
                                        Rectangle()
                                            .strokeBorder(
                                                selected ? AppTheme.primary.opacity(0.55) : Color.clear,
                                                lineWidth: 1
                                            )
                                    }
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .overlay(alignment: .topTrailing) {
                    if model.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(16)
                    }
                }

                Text("共 \(displayDemands.count) 条需求")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .background(AppTheme.surface)
    }

    /// 设计预览仍本地滤；生产列表已由服务端 keyword/nearby 过滤
    private var displayDemands: [Demand] {
        guard isDesignPreview else { return model.demands }
        return model.demands.filter { demand in
            let matchesNearby = !showNearbyOnly || demand.allowNearby
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesQuery = query.isEmpty
                || demand.title.localizedCaseInsensitiveContains(query)
                || demand.expectedOutcome.localizedCaseInsensitiveContains(query)
                || demand.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) })
            return matchesNearby && matchesQuery
        }
    }
}

// MARK: - Fixtures

enum DesignPreviewFixtures {
    static let publisher = AppUser(
        id: "preview-publisher",
        name: "林夏",
        avatarUrl: nil,
        coverUrl: nil,
        demandCardCoverUrl: nil,
        creditScore: 86,
        completedOrders: 23,
        goodRate: 0.98
    )

    static let demands: [Demand] = [
        demand("01", "帮忙整理产品需求与用户反馈", "输出一份结构清晰的需求文档与用户反馈分析报告，包含需求清单、优先级建议及关键洞察。", 600, "1.2 km", "12:48", ["产品设计", "用户研究"]),
        demand("02", "小程序交互流程优化建议", "梳理关键流程并提出可落地的交互优化建议。", 450, "2.4 km", "01:35:20", ["产品设计", "交互设计"]),
        demand("03", "竞品功能体验报告", "对核心竞品做功能体验和差异化分析。", 550, "3.1 km", "03:22:10", ["产品分析", "用户研究"]),
        demand("04", "用户访谈记录整理与分析", "整理访谈纪要并归纳用户诉求与机会点。", 500, "4.6 km", "05:47:33", ["用户研究", "数据分析"]),
        demand("05", "产品文档排版与结构优化", "优化文档结构、层级与可读性。", 300, "5.3 km", "08:16:05", ["产品设计", "内容设计"]),
        demand("06", "生成式 AI 产品调研", "调研生成式 AI 产品能力与行业应用。", 700, "6.8 km", "10:03:44", ["产品分析", "行业研究"])
    ]

    private static func demand(
        _ id: String,
        _ title: String,
        _ outcome: String,
        _ points: Decimal,
        _ distance: String,
        _ countdown: String,
        _ tags: [String]
    ) -> Demand {
        Demand(
            id: "preview-\(id)",
            title: title,
            expectedOutcome: outcome,
            minPrice: points,
            expectedPrice: points,
            deposit: points,
            mediaUrls: [],
            lifecycleStage: "ACTIVE",
            distanceText: distance,
            countdownText: countdown,
            applicantCount: 3,
            applicantLimit: 10,
            tags: tags,
            state: .normal,
            publisher: publisher,
            deadlineText: "2025-05-25（周日）18:00 前",
            isCertifiedOnly: true,
            allowNearby: true,
            status: .active
        )
    }
}

// MARK: - Row

struct DemandRowView: View {
    let demand: Demand
    var isSelected: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(demand.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.onSurface)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if !demand.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(demand.tags.prefix(2).enumerated()), id: \.element) { index, tag in
                            NWStatusChip(text: tag, tint: tagTint(for: tag, index: index))
                        }
                    }
                }

                Text("\(demand.minPrice.currencyText) · \(demand.distanceText)")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(demand.countdownText)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.error)
                Text("剩余可见")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tagTint(for tag: String, index: Int) -> Color {
        if tag.contains("研究") || tag.contains("分析") {
            return AppTheme.openStatus
        }
        return index == 0 ? AppTheme.primary : AppTheme.openStatus
    }
}

/// `03-discover` 搜索栏：放大镜在右侧（对齐渲染图）。
private struct DiscoverSearchBar: View {
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            TextField("搜索需求关键词", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit { onSubmit?() }
            Button {
                onSubmit?()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            AppTheme.surfaceLow,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
        }
    }
}
