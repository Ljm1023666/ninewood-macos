import SwiftUI

/// 收藏（渲染图 24）：设计预览走 fixtures，线上模式走 UserService / DemandRepository。
struct FavoritesView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case demands = "需求"
        case serviceCards = "服务卡"
        var id: String { rawValue }
    }

    /// 非 nil 时启用设计 fixtures（忽略传入数组内容，仅作模式开关）。
    private let previewDemands: [Demand]?

    @Environment(AppSession.self) private var session
    @State private var tab: Tab = .demands
    @State private var keyword = ""
    @State private var selectedID: String
    @State private var isFavorited = true
    @State private var liveDemands: [Demand] = []
    @State private var liveCards: [ServiceCardDTO] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var sortMode: SortMode = .recent

    private enum SortMode: String, CaseIterable, Identifiable {
        case recent = "最近收藏"
        case title = "标题"
        case publisher = "发布者"
        var id: String { rawValue }
    }

    private var usesFixtures: Bool { previewDemands != nil }

    init(previewDemands: [Demand]? = nil) {
        self.previewDemands = previewDemands
        _selectedID = State(
            initialValue: previewDemands != nil
                ? (FavoritesDesignFixtures.items.first?.id ?? "")
                : ""
        )
    }

    private var filteredFixtures: [FavoritesDesignItem] {
        let base = FavoritesDesignFixtures.items.filter { item in
            tab == .demands ? item.kind == .demand : item.kind == .serviceCard
        }
        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.publisherName.localizedCaseInsensitiveContains(q)
                || $0.tags.joined(separator: " ").localizedCaseInsensitiveContains(q)
        }
    }

    private var filteredDemands: [Demand] {
        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        var items = liveDemands
        if !q.isEmpty {
            items = items.filter {
                $0.title.localizedCaseInsensitiveContains(q)
                    || $0.publisher.name.localizedCaseInsensitiveContains(q)
                    || $0.tags.joined(separator: " ").localizedCaseInsensitiveContains(q)
            }
        }
        switch sortMode {
        case .recent:
            break
        case .title:
            items.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .publisher:
            items.sort { $0.publisher.name.localizedStandardCompare($1.publisher.name) == .orderedAscending }
        }
        return items
    }

    private var filteredCards: [ServiceCardDTO] {
        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        var items = liveCards
        if !q.isEmpty {
            items = items.filter {
                $0.title.localizedCaseInsensitiveContains(q)
                    || ($0.publisher?.nickname ?? "").localizedCaseInsensitiveContains(q)
                    || ($0.tags ?? []).joined(separator: " ").localizedCaseInsensitiveContains(q)
            }
        }
        switch sortMode {
        case .recent:
            break
        case .title:
            items.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .publisher:
            items.sort {
                ($0.publisher?.nickname ?? "").localizedStandardCompare($1.publisher?.nickname ?? "") == .orderedAscending
            }
        }
        return items
    }

    private var selectedFixture: FavoritesDesignItem? {
        filteredFixtures.first(where: { $0.id == selectedID }) ?? filteredFixtures.first
    }

    private var selectedDemand: Demand? {
        filteredDemands.first(where: { $0.id == selectedID }) ?? filteredDemands.first
    }

    private var selectedCard: ServiceCardDTO? {
        filteredCards.first(where: { $0.id == selectedID }) ?? filteredCards.first
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            HStack(spacing: 0) {
                listPane
                    .paneColumn(minWidth: 300, idealWidth: 340)
                Divider()
                Group {
                    if usesFixtures {
                        if let selectedFixture {
                            FavoritesDetailPane(
                                item: selectedFixture,
                                isFavorited: $isFavorited
                            )
                            .nwStableDetailIdentity(selectedFixture.id)
                        } else {
                            fixturePlaceholder
                        }
                    } else if tab == .serviceCards {
                        if let selectedCard {
                            FavoritesServiceCardDetail(card: selectedCard) {
                                Task { await unfavoriteCard(selectedCard.id) }
                            }
                            .nwStableDetailIdentity(selectedCard.id)
                        } else if isLoading {
                            ProgressView("加载中…")
                        } else if let loadError {
                            NWEmptyState(title: "加载失败", systemImage: "wifi.exclamationmark", message: loadError)
                        } else {
                            NWDetailPlaceholder(
                                title: "选择收藏的服务卡",
                                systemImage: "star",
                                message: "从左侧列表查看详情"
                            )
                        }
                    } else if let selectedDemand {
                        DemandDetailView(demand: selectedDemand, previewMode: false)
                            .transaction { $0.animation = nil }
                    } else if isLoading {
                        ProgressView("加载中…")
                    } else if let loadError {
                        NWEmptyState(title: "加载失败", systemImage: "wifi.exclamationmark", message: loadError)
                    } else {
                        NWDetailPlaceholder(
                            title: "选择收藏的需求",
                            systemImage: "star",
                            message: "从左侧列表查看详情"
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("收藏")
        .task { await load() }
        .onChange(of: tab) { _, _ in
            if usesFixtures {
                selectedID = filteredFixtures.first?.id ?? ""
                isFavorited = true
            } else {
                isFavorited = true
                Task { await load() }
            }
            keyword = ""
        }
    }

    private var fixturePlaceholder: some View {
        NWDetailPlaceholder(
            title: tab == .demands ? "选择收藏的需求" : "选择收藏的服务卡",
            systemImage: "star",
            message: "从左侧列表查看详情"
        )
    }

    private func load() async {
        guard !usesFixtures else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            if tab == .demands {
                let page = try await session.userService.favorites()
                liveDemands = page.demands.map(DemandMapper.mapListItem)
                liveCards = []
                if selectedID.isEmpty || !liveDemands.contains(where: { $0.id == selectedID }) {
                    selectedID = liveDemands.first?.id ?? ""
                }
            } else {
                liveCards = try await session.userService.favoriteCards()
                liveDemands = []
                if selectedID.isEmpty || !liveCards.contains(where: { $0.id == selectedID }) {
                    selectedID = liveCards.first?.id ?? ""
                }
            }
        } catch {
            liveDemands = []
            liveCards = []
            selectedID = ""
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func unfavoriteCard(_ id: String) async {
        do {
            try await session.userService.toggleFavoriteCard(cardId: id)
            await load()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var headerBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 0) {
                ForEach(Tab.allCases) { item in
                    Button {
                        tab = item
                    } label: {
                        Text(item.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tab == item ? AppTheme.primary : AppTheme.secondaryLabel)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(tab == item ? AppTheme.primary : Color.clear)
                                    .frame(height: 2)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 12)

            NWSearchBar(
                text: $keyword,
                placeholder: tab == .demands ? "搜索收藏的需求" : "搜索收藏的服务卡"
            )
            .frame(width: 220)

            Menu {
                ForEach(SortMode.allCases) { mode in
                    Button {
                        sortMode = mode
                    } label: {
                        if sortMode == mode {
                            Label(mode.rawValue, systemImage: "checkmark")
                        } else {
                            Text(mode.rawValue)
                        }
                    }
                }
            } label: {
                Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                    )
            }
            .menuStyle(.borderlessButton)
            .help("排序方式")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(AppTheme.surface)
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            if usesFixtures {
                fixtureListPane
            } else if tab == .serviceCards {
                if isLoading && liveCards.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                    Spacer(minLength: 0)
                } else if let loadError, liveCards.isEmpty {
                    NWEmptyState(title: "加载失败", systemImage: "wifi.exclamationmark", message: loadError)
                    Spacer(minLength: 0)
                } else if filteredCards.isEmpty {
                    NWEmptyState(
                        title: "暂无收藏",
                        systemImage: "star",
                        message: keyword.isEmpty ? "收藏的服务卡会出现在这里" : "没有匹配结果"
                    )
                    Spacer(minLength: 0)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredCards) { card in
                                Button {
                                    selectedID = card.id
                                    isFavorited = true
                                } label: {
                                    FavoritesLiveCardRow(
                                        card: card,
                                        isSelected: card.id == selectedCard?.id
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                    }
                    Text("共 \(filteredCards.count) 条收藏")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
            } else if isLoading && liveDemands.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                Spacer(minLength: 0)
            } else if let loadError, liveDemands.isEmpty {
                NWEmptyState(title: "加载失败", systemImage: "wifi.exclamationmark", message: loadError)
                Spacer(minLength: 0)
            } else if filteredDemands.isEmpty {
                NWEmptyState(
                    title: "暂无收藏",
                    systemImage: "star",
                    message: keyword.isEmpty ? "收藏的需求会出现在这里" : "没有匹配结果"
                )
                Spacer(minLength: 0)
            } else {
                liveListPane
            }
        }
    }

    private var fixtureListPane: some View {
        Group {
            if filteredFixtures.isEmpty {
                NWEmptyState(
                    title: "暂无收藏",
                    systemImage: "star",
                    message: tab == .demands ? "收藏的需求会出现在这里" : "收藏的服务卡会出现在这里"
                )
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredFixtures) { item in
                            Button {
                                selectedID = item.id
                                isFavorited = true
                            } label: {
                                FavoritesListRow(
                                    item: item,
                                    isSelected: item.id == selectedFixture?.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }

                Text("共 \(filteredFixtures.count) 条收藏")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
    }

    private var liveListPane: some View {
        Group {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredDemands) { demand in
                        Button {
                            selectedID = demand.id
                            isFavorited = true
                        } label: {
                            FavoritesLiveListRow(
                                demand: demand,
                                isSelected: demand.id == selectedDemand?.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }

            Text("共 \(filteredDemands.count) 条收藏")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryLabel)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
    }
}

// MARK: - List row

private struct FavoritesLiveListRow: View {
    let demand: Demand
    var isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(demand.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.onSurface)
                    .lineLimit(2)
                Spacer(minLength: 6)
                FavoritesStatusChip(status: FavoritesStatusMapper.status(for: demand.status))
            }

            HStack(spacing: 12) {
                Text("预算 \(demand.minPrice.pointsText)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.onSurface)
                Text(demand.publisher.name)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }

            HStack(spacing: 8) {
                Text(demand.distanceText)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
                Text("·")
                    .foregroundStyle(AppTheme.secondaryLabel)
                Text(demand.status.title)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nwSelectionChrome(isSelected: isSelected, cornerRadius: 10)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? AppTheme.primary : AppTheme.outlineVariant, lineWidth: isSelected ? 1.5 : 1)
        }
    }
}

private struct FavoritesLiveCardRow: View {
    let card: ServiceCardDTO
    var isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.onSurface)
                .lineLimit(2)
            HStack(spacing: 12) {
                if let min = card.priceMin?.value {
                    Text(min.pointsText)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(card.publisher?.nickname ?? "服务者")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            if let tags = card.tags, !tags.isEmpty {
                Text(tags.prefix(3).joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nwSelectionChrome(isSelected: isSelected, cornerRadius: 10)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? AppTheme.primary : AppTheme.outlineVariant, lineWidth: isSelected ? 1.5 : 1)
        }
    }
}

private struct FavoritesServiceCardDetail: View {
    let card: ServiceCardDTO
    var onUnfavorite: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(card.title).font(.title.bold())
                    Spacer()
                    Button("取消收藏", action: onUnfavorite)
                        .buttonStyle(.bordered)
                }
                if let status = card.status {
                    NWStatusChip(text: status)
                }
                Text(card.description ?? card.summary ?? "")
                    .foregroundStyle(.secondary)
                if let tags = card.tags, !tags.isEmpty {
                    Text(tags.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let publisher = card.publisher {
                    Text("发布者：\(publisher.nickname ?? "用户")")
                        .font(.subheadline)
                }
            }
            .padding(AppTheme.horizontalPadding)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.workspaceBackground)
    }
}

private enum FavoritesStatusMapper {
    static func status(for demandStatus: DemandStatus) -> FavoritesDesignStatus {
        switch demandStatus {
        case .active: .recruiting
        case .inProgress: .inProgress
        case .completed, .withdrawn, .cancelled, .draft: .ended
        case .frozen: .expired
        case .unknown: .recruiting
        }
    }
}

private struct FavoritesListRow: View {
    let item: FavoritesDesignItem
    var isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.onSurface)
                    .lineLimit(2)
                Spacer(minLength: 6)
                FavoritesStatusChip(status: item.status)
            }

            HStack(spacing: 12) {
                Text(item.budgetText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.onSurface)
                Text(item.favoritedAt)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }

            HStack(spacing: 8) {
                Text(item.locationText)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
                Text("·")
                    .foregroundStyle(AppTheme.secondaryLabel)
                Text(item.visibilityText)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nwSelectionChrome(isSelected: isSelected, cornerRadius: 10)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? AppTheme.primary : AppTheme.outlineVariant, lineWidth: isSelected ? 1.5 : 1)
        }
    }
}

private struct FavoritesStatusChip: View {
    let status: FavoritesDesignStatus

    var body: some View {
        Text(status.label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(status.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.tint.opacity(0.12), in: Capsule(style: .continuous))
    }
}

// MARK: - Detail

private struct FavoritesDetailPane: View {
    let item: FavoritesDesignItem
    @Binding var isFavorited: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    titleBlock
                    publisherCard
                    section(title: "期望成果") {
                        Text(item.expectedOutcome)
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    financials
                    section(title: "需求描述") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(item.descriptionBullets, id: \.self) { bullet in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundStyle(AppTheme.secondaryLabel)
                                    Text(bullet)
                                        .font(.system(size: 13))
                                        .foregroundStyle(AppTheme.secondaryLabel)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    section(title: "标签") {
                        HStack(spacing: 8) {
                            ForEach(item.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AppTheme.secondaryLabel)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(AppTheme.surfaceLow, in: Capsule(style: .continuous))
                                    .overlay {
                                        Capsule(style: .continuous)
                                            .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                                    }
                            }
                        }
                    }
                    if let attachment = item.attachment {
                        section(title: "附件") {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.richtext")
                                    .font(.system(size: 22))
                                    .foregroundStyle(AppTheme.error.opacity(0.85))
                                    .frame(width: 40, height: 40)
                                    .background(AppTheme.error.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(attachment.name)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(attachment.sizeText)
                                        .font(.system(size: 11))
                                        .foregroundStyle(AppTheme.secondaryLabel)
                                }
                                Spacer()
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(AppTheme.primary)
                            }
                            .padding(12)
                            .background(AppTheme.surfaceLow, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    progressSection
                }
                .padding(24)
                .frame(maxWidth: 760, alignment: .leading)
            }

            Divider()
            actionBar
        }
        .background(AppTheme.workspaceBackground)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(item.title)
                    .font(.system(size: 20, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 6) {
                    Text("共 12 条")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                    FavoritesStatusChip(status: item.status)
                    Text("收藏于 \(item.favoritedAt)")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                    Text(item.visibilityText)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
            }
        }
    }

    private var publisherCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.openStatus.opacity(0.18))
                Text(String(item.publisherName.prefix(1)))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.openStatus)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text(item.publisherName)
                        .font(.system(size: 14, weight: .semibold))
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.primary)
                }
                HStack(spacing: 8) {
                    ForEach(item.publisherBadges, id: \.self) { badge in
                        Text(badge)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppTheme.surfaceLow, in: Capsule(style: .continuous))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            content()
        }
    }

    private var financials: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("预算")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
                Text(item.budgetText)
                    .font(.system(size: 16, weight: .bold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("托管金额")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
                Text(item.escrowText)
                    .font(.system(size: 16, weight: .bold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(AppTheme.surfaceLow, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("申请进展")
                .font(.system(size: 14, weight: .semibold))
            HStack(spacing: 0) {
                ForEach(Array(item.progress.enumerated()), id: \.element.id) { index, step in
                    FavoritesProgressStep(step: step, isLast: index == item.progress.count - 1)
                }
            }
        }
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {} label: {
                Text("请求接单")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                isFavorited.toggle()
            } label: {
                Text(isFavorited ? "取消收藏" : "重新收藏")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.onSurface)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(AppTheme.surface)
    }
}

private struct FavoritesProgressStep: View {
    let step: FavoritesProgressStepModel
    var isLast: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(step.state == .pending ? AppTheme.fill : AppTheme.primary)
                        .frame(width: 24, height: 24)
                    switch step.state {
                    case .done:
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    case .active:
                        Text("\(step.index)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    case .pending:
                        Text("\(step.index)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                }
                Text(step.title)
                    .font(.system(size: 11, weight: step.state == .active ? .semibold : .regular))
                    .foregroundStyle(step.state == .pending ? AppTheme.secondaryLabel : AppTheme.onSurface)
                Text(step.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            .frame(maxWidth: .infinity)

            if !isLast {
                Rectangle()
                    .fill(step.state == .done ? AppTheme.primary.opacity(0.45) : AppTheme.outlineVariant)
                    .frame(width: 28, height: 2)
                    .offset(y: -18)
            }
        }
    }
}

// MARK: - Models & fixtures

enum FavoritesDesignKind {
    case demand
    case serviceCard
}

enum FavoritesDesignStatus {
    case recruiting
    case inProgress
    case ended
    case expired

    var label: String {
        switch self {
        case .recruiting: "招募中"
        case .inProgress: "进行中"
        case .ended: "已结束"
        case .expired: "已过期"
        }
    }

    var tint: Color {
        switch self {
        case .recruiting: AppTheme.openStatus
        case .inProgress: AppTheme.primary
        case .ended: AppTheme.secondaryLabel
        case .expired: AppTheme.error
        }
    }
}

enum FavoritesProgressState {
    case done, active, pending
}

struct FavoritesProgressStepModel: Identifiable, Hashable {
    let id: String
    let index: Int
    let title: String
    let subtitle: String
    let state: FavoritesProgressState
}

struct FavoritesAttachment: Hashable {
    let name: String
    let sizeText: String
}

struct FavoritesDesignItem: Identifiable, Hashable {
    let id: String
    let kind: FavoritesDesignKind
    let title: String
    let status: FavoritesDesignStatus
    let budgetText: String
    let escrowText: String
    let favoritedAt: String
    let locationText: String
    let visibilityText: String
    let publisherName: String
    let publisherBadges: [String]
    let expectedOutcome: String
    let descriptionBullets: [String]
    let tags: [String]
    let attachment: FavoritesAttachment?
    let progress: [FavoritesProgressStepModel]
}

enum FavoritesDesignFixtures {
    static let items: [FavoritesDesignItem] = [
        FavoritesDesignItem(
            id: "fav-1",
            kind: .demand,
            title: "可持续包装用户调研",
            status: .recruiting,
            budgetText: "预算 ¥ 18,000",
            escrowText: "¥ 9,000（平台托管）",
            favoritedAt: "今天 10:24",
            locationText: "在线 · 远程协作",
            visibilityText: "公开可见",
            publisherName: "GreenLoop 绿环科技",
            publisherBadges: ["企业认证", "发包 16", "完成 12", "好评率 100%"],
            expectedOutcome: "输出一份面向可持续包装决策的用户调研报告，覆盖目标用户画像、使用场景痛点、包装偏好与可落地的设计建议，并附原始访谈纪要与优先级清单。",
            descriptionBullets: [
                "完成 8–12 场用户访谈，覆盖家庭与小微商户两类场景",
                "梳理包装决策链路与关键阻碍，形成结构化洞察",
                "给出可执行的包装方向建议与验证指标",
                "交付可匿名复用的过程记录与最终报告"
            ],
            tags: ["用户研究", "可持续发展", "包装设计", "访谈"],
            attachment: FavoritesAttachment(name: "可持续包装调研背景资料.pdf", sizeText: "1.2 MB"),
            progress: [
                FavoritesProgressStepModel(id: "p1", index: 1, title: "需求发布", subtitle: "5月20日", state: .done),
                FavoritesProgressStepModel(id: "p2", index: 2, title: "招募中", subtitle: "5月20–27日", state: .active),
                FavoritesProgressStepModel(id: "p3", index: 3, title: "评估中", subtitle: "即将开始", state: .pending),
                FavoritesProgressStepModel(id: "p4", index: 4, title: "已选定", subtitle: "未开始", state: .pending)
            ]
        ),
        FavoritesDesignItem(
            id: "fav-2",
            kind: .demand,
            title: "帮忙整理产品需求与用户反馈",
            status: .inProgress,
            budgetText: "预算 ¥ 600",
            escrowText: "¥ 600（平台托管）",
            favoritedAt: "昨天 16:08",
            locationText: "1.2 km · 位置已模糊",
            visibilityText: "公开可见",
            publisherName: "林夏",
            publisherBadges: ["个人认证", "发包 8", "完成 6", "好评率 98%"],
            expectedOutcome: "输出结构清晰的需求文档与用户反馈分析报告。",
            descriptionBullets: [
                "整理需求清单并标注优先级",
                "归纳关键用户反馈与机会点",
                "保留过程记录便于验收"
            ],
            tags: ["产品设计", "用户研究"],
            attachment: nil,
            progress: [
                FavoritesProgressStepModel(id: "p1", index: 1, title: "需求发布", subtitle: "已完成", state: .done),
                FavoritesProgressStepModel(id: "p2", index: 2, title: "招募中", subtitle: "已完成", state: .done),
                FavoritesProgressStepModel(id: "p3", index: 3, title: "评估中", subtitle: "进行中", state: .active),
                FavoritesProgressStepModel(id: "p4", index: 4, title: "已选定", subtitle: "未开始", state: .pending)
            ]
        ),
        FavoritesDesignItem(
            id: "fav-3",
            kind: .demand,
            title: "小程序交互流程优化建议",
            status: .ended,
            budgetText: "预算 ¥ 450",
            escrowText: "¥ 450（平台托管）",
            favoritedAt: "7月15日",
            locationText: "在线 · 远程协作",
            visibilityText: "公开可见",
            publisherName: "程野",
            publisherBadges: ["个人认证", "发包 5", "完成 4"],
            expectedOutcome: "梳理关键流程并提出可落地的交互优化建议。",
            descriptionBullets: [
                "绘制关键路径并标注断点",
                "给出优化方案与优先级"
            ],
            tags: ["产品设计", "交互设计"],
            attachment: nil,
            progress: [
                FavoritesProgressStepModel(id: "p1", index: 1, title: "需求发布", subtitle: "已完成", state: .done),
                FavoritesProgressStepModel(id: "p2", index: 2, title: "招募中", subtitle: "已完成", state: .done),
                FavoritesProgressStepModel(id: "p3", index: 3, title: "评估中", subtitle: "已完成", state: .done),
                FavoritesProgressStepModel(id: "p4", index: 4, title: "已选定", subtitle: "已结束", state: .done)
            ]
        ),
        FavoritesDesignItem(
            id: "fav-4",
            kind: .demand,
            title: "竞品功能体验报告",
            status: .expired,
            budgetText: "预算 ¥ 550",
            escrowText: "¥ 550（平台托管）",
            favoritedAt: "7月12日",
            locationText: "在线 · 远程协作",
            visibilityText: "公开可见",
            publisherName: "乔安",
            publisherBadges: ["个人认证", "发包 3"],
            expectedOutcome: "对核心竞品做功能体验和差异化分析。",
            descriptionBullets: [
                "覆盖 3–5 款竞品",
                "输出差异化结论与机会建议"
            ],
            tags: ["产品分析", "用户研究"],
            attachment: nil,
            progress: [
                FavoritesProgressStepModel(id: "p1", index: 1, title: "需求发布", subtitle: "已完成", state: .done),
                FavoritesProgressStepModel(id: "p2", index: 2, title: "招募中", subtitle: "已过期", state: .pending),
                FavoritesProgressStepModel(id: "p3", index: 3, title: "评估中", subtitle: "未开始", state: .pending),
                FavoritesProgressStepModel(id: "p4", index: 4, title: "已选定", subtitle: "未开始", state: .pending)
            ]
        ),
        FavoritesDesignItem(
            id: "fav-card-1",
            kind: .serviceCard,
            title: "品牌视觉与产品图标设计",
            status: .recruiting,
            budgetText: "¥800 – ¥1,200",
            escrowText: "按确认范围托管",
            favoritedAt: "今天 09:12",
            locationText: "在线 · 远程协作",
            visibilityText: "公开可见",
            publisherName: "周屿",
            publisherBadges: ["PRO", "完成 46", "好评率 99%"],
            expectedOutcome: "从风格探索到多端图标交付，包含源文件与一次集中修改。",
            descriptionBullets: [
                "品牌图形与产品图标一体化设计",
                "多尺寸导出与基础使用规范"
            ],
            tags: ["图标设计", "品牌升级", "多端适配"],
            attachment: nil,
            progress: [
                FavoritesProgressStepModel(id: "p1", index: 1, title: "已发布", subtitle: "公开", state: .done),
                FavoritesProgressStepModel(id: "p2", index: 2, title: "可咨询", subtitle: "进行中", state: .active),
                FavoritesProgressStepModel(id: "p3", index: 3, title: "确认范围", subtitle: "未开始", state: .pending),
                FavoritesProgressStepModel(id: "p4", index: 4, title: "开始履约", subtitle: "未开始", state: .pending)
            ]
        )
    ]
}
