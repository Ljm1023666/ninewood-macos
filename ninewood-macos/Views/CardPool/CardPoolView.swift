import SwiftUI

struct CardPoolView: View {
    @Environment(AppSession.self) private var session
    @State private var poolTab: PoolTab = .active
    @State private var demands: [Demand] = []
    @State private var selectedDemand: Demand?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showMyServiceCards = false
    @State private var searchText = ""
    @State private var category = "全部类目"
    @State private var serviceMode = "服务模式"
    @State private var sortOrder = "默认排序"
    @State private var currentPage = 1
    @State private var snatchCredits: Int?
    @State private var certifiedOnly = false
    private let previewDemands: [Demand]?

    init(previewDemands: [Demand]? = nil, initialTab: PoolTab = .active) {
        self.previewDemands = previewDemands
        _poolTab = State(initialValue: initialTab)
    }

    private var isDesignPreview: Bool { previewDemands != nil }

    enum PoolTab: String, CaseIterable, Identifiable {
        case active = "进行中"
        case dead = "死池"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                listPane
                    .paneColumn(minWidth: 540, idealWidth: 580)
                Divider()
                Group {
                    if let selectedDemand {
                        Group {
                            if poolTab == .active {
                                if isDesignPreview {
                                    CardPoolReferenceDetail(
                                        demand: selectedDemand,
                                        useDesignAvatar: true,
                                        onOpenServiceCards: { showMyServiceCards = true }
                                    )
                                } else {
                                    DemandDetailView(
                                        demand: selectedDemand,
                                        poolMode: .activePool,
                                        previewMode: false
                                    )
                                }
                            } else {
                                DemandDetailView(
                                    demand: selectedDemand,
                                    poolMode: .deadPool,
                                    previewMode: isDesignPreview
                                )
                            }
                        }
                        .nwStableDetailIdentity(selectedDemand.id)
                    } else {
                        NWDetailPlaceholder(
                            title: "选择需求",
                            systemImage: "square.stack.3d.up",
                            message: "从左侧卡池选择一条需求查看详情"
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("卡池")
            .toolbar {
                if !isDesignPreview, let snatchCredits {
                    ToolbarItem(placement: .status) {
                        Text("抢单额度 \(snatchCredits)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("GET /users/snatch-status")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("刷新")
                    .disabled(isLoading)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showMyServiceCards = true
                    } label: {
                        Label("服务卡", systemImage: "rectangle.on.rectangle")
                    }
                }
            }
            .sheet(isPresented: $showMyServiceCards) {
                NavigationStack {
                    MyServiceCardsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") { showMyServiceCards = false }
                            }
                        }
                }
                .frame(minWidth: 520, minHeight: 420)
            }
        }
        .task { await load() }
        .onChange(of: poolTab) { _, _ in
            selectedDemand = nil
            currentPage = 1
            Task { await load() }
        }
        .onChange(of: session.navigation.request) { _, _ in
            guard !isDesignPreview else { return }
            let wantDead = session.navigation.currentPath == "/card-pool/dead"
            let next: PoolTab = wantDead ? .dead : .active
            if poolTab != next {
                poolTab = next
            }
        }
    }

    // MARK: - List

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            poolTabControl
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            if poolTab == .dead {
                Text("过期未成交的需求进入死池，可尝试抢单。")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            if poolTab == .active {
                filterBar
                tableHeader
            }

            if let loadError {
                VStack(alignment: .leading, spacing: AppTheme.space8) {
                    Text(loadError).foregroundStyle(.secondary)
                    Button("重新加载") { Task { await load() } }
                }
                .padding(AppTheme.space16)
                Spacer(minLength: 0)
            } else if isLoading && demands.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                Spacer(minLength: 0)
            } else if filteredDemands.isEmpty {
                NWEmptyState(
                    title: poolTab == .active ? "暂无进行中的需求" : "死池暂无需求",
                    systemImage: "tray",
                    message: poolTab == .active
                        ? "卡池会汇总可竞价 / 可接的公开需求"
                        : "过期未成交的需求会进入死池，可尝试抢单"
                )
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(pagedDemands) { demand in
                            Button {
                                selectedDemand = demand
                            } label: {
                                poolRow(demand, selected: selectedDemand?.id == demand.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }

                if poolTab == .active {
                    listFooter
                }
            }
        }
    }

    private var poolTabControl: some View {
        HStack(spacing: 0) {
            ForEach(PoolTab.allCases) { tab in
                Button {
                    poolTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(poolTab == tab ? Color.white : AppTheme.secondaryLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(poolTab == tab ? AppTheme.primary : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.fill.opacity(0.75))
        )
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            NWSearchBar(text: $searchText, placeholder: "搜索需求标题或关键词")
                .frame(minWidth: 160)

            menuPicker(selection: $category, options: ["全部类目", "视觉设计", "界面设计", "内容创作", "数据可视化", "产品策划", "品牌策划"])
            menuPicker(selection: $serviceMode, options: ["服务模式", "一对一", "一对多"])
            menuPicker(selection: $sortOrder, options: ["默认排序", "预算最高", "即将截止"])

            Menu {
                Toggle("仅认证服务者需求", isOn: $certifiedOnly)
                Divider()
                Button("重置筛选") {
                    category = "全部类目"
                    serviceMode = "服务模式"
                    sortOrder = "默认排序"
                    certifiedOnly = false
                    searchText = ""
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(
                        certifiedOnly || category != "全部类目" || serviceMode != "服务模式" || sortOrder != "默认排序"
                            ? AppTheme.primary
                            : AppTheme.secondaryLabel
                    )
                    .frame(width: 30, height: 30)
                    .background(AppTheme.fill.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .help("更多筛选")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func menuPicker(selection: Binding<String>, options: [String]) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(option) { selection.wrappedValue = option }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selection.wrappedValue)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.onSurface)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppTheme.fill.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .frame(minWidth: 72)
    }

    private var tableHeader: some View {
        HStack(spacing: 8) {
            Text("需求标题").frame(maxWidth: .infinity, alignment: .leading)
            Text("奖励(点)").frame(width: 72, alignment: .leading)
            Text("模式").frame(width: 48, alignment: .leading)
            Text("剩余可见").frame(width: 72, alignment: .leading)
            Text("应标").frame(width: 36, alignment: .trailing)
            Text("认证").frame(width: 48, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(AppTheme.secondaryLabel)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.outlineVariant)
                .frame(height: 1)
        }
    }

    private func poolRow(_ demand: Demand, selected: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text(demand.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.onSurface)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let tag = demand.tags.first {
                    Text(tag)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppTheme.primary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AppTheme.softPrimary)
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(rewardRangeText(demand))
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.onSurface)
                .frame(width: 72, alignment: .leading)

            Text(serviceModeText(demand))
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.onSurface)
                .frame(width: 48, alignment: .leading)

            Text(countdownDisplay(demand.countdownText))
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.onSurface)
                .frame(width: 72, alignment: .leading)

            Text("\(demand.applicantCount)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.onSurface)
                .frame(width: 36, alignment: .trailing)

            Text(demand.isCertifiedOnly ? "需认证" : "不限")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(demand.isCertifiedOnly ? AppTheme.urgent : AppTheme.secondaryLabel)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
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
                    selected ? AppTheme.primary.opacity(0.45) : Color.clear,
                    lineWidth: 1
                )
        }
        .contentShape(Rectangle())
    }

    private var listFooter: some View {
        HStack(spacing: 12) {
            Text("共 \(totalCount) 条")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondaryLabel)

            Spacer()

            HStack(spacing: 6) {
                pageArrow(systemImage: "chevron.left", disabled: currentPage <= 1) {
                    currentPage = max(1, currentPage - 1)
                }
                ForEach(1...pageCount, id: \.self) { page in
                    Button {
                        currentPage = page
                    } label: {
                        Text("\(page)")
                            .font(.system(size: 12, weight: page == currentPage ? .semibold : .regular))
                            .foregroundStyle(page == currentPage ? Color.white : AppTheme.onSurface)
                            .frame(width: 26, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(page == currentPage ? AppTheme.primary : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
                pageArrow(systemImage: "chevron.right", disabled: currentPage >= pageCount) {
                    currentPage = min(pageCount, currentPage + 1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.outlineVariant)
                .frame(height: 1)
        }
    }

    private func pageArrow(systemImage: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(disabled ? AppTheme.secondaryLabel.opacity(0.4) : AppTheme.secondaryLabel)
                .frame(width: 24, height: 26)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - Data

    private var filteredDemands: [Demand] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var items = demands.filter { demand in
            let matchesQuery = query.isEmpty
                || demand.title.localizedCaseInsensitiveContains(query)
                || demand.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) })
            let matchesCategory = category == "全部类目" || demand.tags.contains(category)
            let matchesMode = serviceMode == "服务模式" || serviceModeText(demand) == serviceMode
            let matchesCert = !certifiedOnly || demand.isCertifiedOnly
            return matchesQuery && matchesCategory && matchesMode && matchesCert
        }
        switch sortOrder {
        case "预算最高":
            items.sort { ($0.expectedPrice ?? $0.minPrice) > ($1.expectedPrice ?? $1.minPrice) }
        case "即将截止":
            items.sort { $0.countdownText < $1.countdownText }
        default:
            break
        }
        return items
    }

    private var pageSize: Int { 6 }

    private var totalCount: Int {
        isDesignPreview ? 28 : filteredDemands.count
    }

    private var pageCount: Int {
        max(1, min(3, Int(ceil(Double(max(totalCount, 1)) / Double(pageSize)))))
    }

    private var pagedDemands: [Demand] {
        guard !isDesignPreview else { return filteredDemands }
        let start = (currentPage - 1) * pageSize
        guard start < filteredDemands.count else { return filteredDemands }
        return Array(filteredDemands.dropFirst(start).prefix(pageSize))
    }

    private func rewardRangeText(_ demand: Demand) -> String {
        let min = NSDecimalNumber(decimal: demand.minPrice).intValue
        if let expected = demand.expectedPrice {
            let max = NSDecimalNumber(decimal: expected).intValue
            if max != min { return "\(min)-\(max)" }
        }
        return "\(min)"
    }

    private func serviceModeText(_ demand: Demand) -> String {
        demand.applicantLimit <= 1 ? "一对一" : "一对多"
    }

    private func countdownDisplay(_ text: String) -> String {
        text
            .replacingOccurrences(of: "天", with: "天 ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        if let previewDemands {
            demands = previewDemands
            selectedDemand = previewDemands.first
            return
        }
        do {
            demands = switch poolTab {
            case .active:
                try await session.demandRepository.activePool()
            case .dead:
                try await session.demandRepository.closedPool()
            }
            if let selectedDemand, demands.contains(where: { $0.id == selectedDemand.id }) {
                // keep
            } else {
                self.selectedDemand = demands.first
            }
            if let status = try? await session.userService.snatchStatus() {
                snatchCredits = status.availableCredits
            }
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            demands = []
        }
    }
}

// MARK: - Design preview fixtures

enum CardPoolDesignPreviewFixtures {
    static let demands: [Demand] = [
        item(
            "01",
            "寻找品牌视觉设计师完善产品图标",
            "我们正在迭代产品品牌形象，需要对现有图标系统进行统一风格优化与细节完善，覆盖产品主流程与关键运营场景。",
            800, 1200, "5天 12小时", 12,
            ["视觉设计", "图标设计", "品牌升级", "多端适配"],
            oneToOne: true, certified: true
        ),
        item(
            "02",
            "为我们的开源工具设计官网落地页",
            "梳理信息架构并完成高保真官网设计，突出开源社区气质与产品能力。",
            600, 900, "3天 4小时", 8,
            ["界面设计"],
            oneToOne: false, certified: false
        ),
        item(
            "03",
            "短视频脚本与分镜创作",
            "完成短视频脚本、分镜与拍摄说明，适配种草与转化两类节奏。",
            400, 600, "2天 22小时", 15,
            ["内容创作"],
            oneToOne: true, certified: true
        ),
        item(
            "04",
            "数据可视化看板设计",
            "为业务指标设计清晰的数据看板，兼顾桌面端与大屏展示。",
            1000, 1500, "6天 8小时", 6,
            ["数据可视化"],
            oneToOne: true, certified: true
        ),
        item(
            "05",
            "产品需求文档梳理与优化",
            "重构产品需求文档的信息层级，形成可协作的需求基线。",
            700, 1000, "4天 18小时", 9,
            ["产品策划"],
            oneToOne: false, certified: true
        ),
        item(
            "06",
            "品牌命名与口号创意",
            "提供品牌命名和传播口号方案，附简要释义与使用建议。",
            300, 500, "1天 12小时", 20,
            ["品牌策划"],
            oneToOne: true, certified: false
        )
    ]

    private static func item(
        _ id: String,
        _ title: String,
        _ outcome: String,
        _ min: Decimal,
        _ expected: Decimal,
        _ countdown: String,
        _ applicants: Int,
        _ tags: [String],
        oneToOne: Bool,
        certified: Bool
    ) -> Demand {
        Demand(
            id: "pool-\(id)",
            title: title,
            expectedOutcome: outcome,
            minPrice: min,
            expectedPrice: expected,
            distanceText: "线上",
            countdownText: countdown,
            applicantCount: applicants,
            applicantLimit: 30,
            tags: tags,
            state: .normal,
            publisher: AppUser(
                id: "pool-publisher",
                name: "林止",
                avatarUrl: nil,
                coverUrl: nil,
                demandCardCoverUrl: nil,
                creditScore: 96,
                completedOrders: 9,
                goodRate: 0.99
            ),
            deadlineText: countdown,
            isCertifiedOnly: certified,
            allowNearby: oneToOne,
            status: .active
        )
    }
}

// MARK: - Reference detail (rendering 04)

private struct CardPoolReferenceDetail: View {
    let demand: Demand
    var useDesignAvatar: Bool = false
    var onOpenServiceCards: () -> Void = {}

    private let bidderNames = ["陈", "林", "周", "程", "乔", "王", "吴"]
    private let deliverables = [
        "图标设计（约 30–40 个）",
        "多尺寸导出（1x / 2x / 3x / 4x）",
        "设计规范说明（样式、命名、使用场景）",
        "源文件（Figma 或 Sketch）"
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(demand.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AppTheme.onSurface)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 16)

                    publisherRow
                    sectionDivider()

                    HStack(alignment: .top, spacing: 0) {
                        stat("预算范围", rewardLabel, AppTheme.primary)
                        stat("服务模式", demand.applicantLimit <= 1 ? "一对一" : "一对多")
                        stat("剩余可见", demand.countdownText)
                    }
                    sectionDivider()

                    block("需求简介") {
                        Text(demand.expectedOutcome)
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.onSurface)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    block("交付物") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(deliverables, id: \.self) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundStyle(AppTheme.secondaryLabel)
                                    Text(item)
                                        .font(.system(size: 13))
                                        .foregroundStyle(AppTheme.onSurface)
                                }
                            }
                        }
                    }

                    block("需求标签") {
                        HStack(spacing: 8) {
                            ForEach(demand.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color(red: 0.93, green: 0.94, blue: 0.95))
                                    )
                            }
                        }
                    }

                    block("附件") {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(AppTheme.primary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("现有图标库与使用场景参考.zip")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(AppTheme.onSurface)
                                    .lineLimit(1)
                                Text("28.6 MB")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.down.to.line")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppTheme.secondaryLabel)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppTheme.surfaceLow)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                        }
                    }

                    block("应标进展") {
                        HStack {
                            Text("已应标 \(demand.applicantCount) 人")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            HStack(spacing: 2) {
                                Text("查看全部")
                                Text("›")
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        }
                        .padding(.bottom, 10)

                        HStack(spacing: -8) {
                            ForEach(Array(bidderNames.enumerated()), id: \.offset) { _, name in
                                NWAvatarView(url: nil, name: name, size: 30)
                                    .overlay {
                                        Circle().stroke(Color.white, lineWidth: 2)
                                    }
                            }
                            Text("+5")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppTheme.secondaryLabel)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(Color(red: 0.93, green: 0.94, blue: 0.95)))
                                .overlay { Circle().strokeBorder(AppTheme.outlineVariant, lineWidth: 1) }
                                .padding(.leading, 12)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 20)
            }

            Divider()

            HStack(spacing: 12) {
                Button("参与应标") {}
                    .buttonStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .disabled(true)
                    .help("设计预览不可提交应标；线上请在卡池详情操作")

                Button(action: onOpenServiceCards) {
                    Text("查看我的服务卡")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.onSurface)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color(red: 0.82, green: 0.84, blue: 0.86), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(AppTheme.surface)
        }
        .background(AppTheme.surface)
    }

    private var publisherRow: some View {
        HStack(spacing: 10) {
            if useDesignAvatar {
                Image("AvatarZhangMo")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                    .overlay { Circle().strokeBorder(AppTheme.outlineVariant, lineWidth: 1) }
            } else {
                NWAvatarView(url: demand.publisher.avatarMediaURL, name: demand.publisher.name, size: 36)
            }

            Text(demand.publisher.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.onSurface)

            Text("可信赖")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule(style: .continuous).fill(AppTheme.openStatus))

            Text("累计发布 18 · 成功完成 \(demand.publisher.completedOrders)")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondaryLabel)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    private var rewardLabel: String {
        let min = NSDecimalNumber(decimal: demand.minPrice).intValue
        let max = NSDecimalNumber(decimal: demand.expectedPrice ?? demand.minPrice).intValue
        return "\(min) - \(max) 点"
    }

    private func sectionDivider() -> some View {
        Rectangle()
            .fill(AppTheme.fill)
            .frame(height: 1)
            .padding(.vertical, 18)
    }

    private func stat(_ title: String, _ value: String, _ color: Color = AppTheme.onSurface) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryLabel)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func block<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.onSurface)
            content()
        }
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - My service cards sheet

private struct MyServiceCardsView: View {
    @Environment(AppSession.self) private var session
    @State private var cards: [ServiceCardDTO] = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        Group {
            if let loadError {
                NWEmptyState(title: "加载失败", systemImage: "exclamationmark.triangle", message: loadError)
            } else if isLoading && cards.isEmpty {
                ProgressView()
            } else if cards.isEmpty {
                NWEmptyState(title: "暂无服务卡", systemImage: "rectangle.stack", message: "发布服务卡后会出现在这里")
            } else {
                List(cards) { card in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(card.title).font(.headline)
                        if let summary = card.summary ?? card.description {
                            Text(summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        HStack {
                            if let category = card.category {
                                Text(category).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let status = card.status {
                                NWStatusChip(text: status)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.workspaceBackground)
        .navigationTitle("我的服务卡")
        .task { await load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("刷新") { Task { await load() } }
            }
        }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            cards = try await session.serviceCardService.mine()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
