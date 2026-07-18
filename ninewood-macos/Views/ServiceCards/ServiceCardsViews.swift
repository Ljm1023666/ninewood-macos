import SwiftUI

struct ServiceCardsManageView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case mine = "我的"
        case market = "市场"
        var id: String { rawValue }
    }

    @Environment(AppSession.self) private var session
    @State private var mode: Mode = .mine
    @State private var cards: [ServiceCardDTO] = []
    @State private var selected: ServiceCardDTO?
    @State private var showCreate = false
    @State private var message: String?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var marketKeyword = ""
    private let previewCards: [ServiceCardDTO]?

    init(previewCards: [ServiceCardDTO]? = nil) {
        self.previewCards = previewCards
        _cards = State(initialValue: previewCards ?? [])
        _selected = State(initialValue: previewCards?.first)
    }

    private var isPreview: Bool { previewCards != nil }

    var body: some View {
        HStack(spacing: 0) {
            listColumn
            Divider()
            if isPreview {
                manageColumn.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                publicPreviewColumn
            } else {
                detailColumn
            }
        }
        .navigationTitle("服务卡")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if isPreview {
                    Button {} label: {
                        Label("新建服务卡", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    if mode == .mine {
                        Button("新建") { showCreate = true }
                    }
                    Button("刷新") { Task { await load() } }
                }
            }
        }
        .task(id: mode) { await load() }
        .sheet(isPresented: $showCreate) {
            ServiceCardEditorSheet { Task { await load() } }
                .frame(minWidth: 520, minHeight: 480)
        }
        .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("确定", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private var listColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isPreview {
                HStack {
                    Spacer()
                    NWSearchBar(text: $marketKeyword, placeholder: "搜索服务卡")
                        .frame(maxWidth: 180)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                Text("我的服务卡（6）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            } else {
                NWPaneCaption(text: mode == .mine ? "创建、发布你的服务能力" : "搜索已公开的服务卡")
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                if mode == .market {
                    NWSearchBar(text: $marketKeyword, placeholder: "搜索服务卡标题或描述")
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                        .onSubmit { Task { await load() } }
                }
            }

            if isLoading && cards.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 32)
                Spacer(minLength: 0)
            } else if let loadError, cards.isEmpty {
                NWEmptyState(title: "服务卡加载失败", systemImage: "wifi.exclamationmark", message: loadError)
                Spacer(minLength: 0)
            } else if cards.isEmpty {
                NWEmptyState(
                    title: mode == .mine ? "暂无服务卡" : "暂无公开服务卡",
                    systemImage: "rectangle.stack",
                    message: mode == .mine ? "创建一张服务卡，展示你的能力" : "试试换个关键词，或稍后再来"
                )
                Spacer(minLength: 0)
            } else if isPreview {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(cards) { card in
                            previewListRow(card)
                        }
                    }
                }
            } else {
                List(cards, selection: $selected) { card in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.title).font(.headline)
                        Text(card.summary ?? card.description ?? "")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        HStack {
                            if let status = card.status {
                                NWStatusChip(text: status)
                            }
                            if mode == .market, let publisher = card.publisher?.nickname {
                                Text(publisher).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tag(card)
                }
                .listStyle(.inset)
            }
        }
        .paneColumn(minWidth: 280, idealWidth: isPreview ? 300 : 340)
    }

    @ViewBuilder
    private var detailColumn: some View {
        Group {
            if let selected {
                if mode == .mine {
                    ServiceCardDetailPane(card: selected) { Task { await load() } }
                } else {
                    ServiceCardPublicDetailView(card: selected)
                }
            } else {
                NWDetailPlaceholder(
                    title: mode == .mine ? "选择服务卡" : "选择公开服务卡",
                    systemImage: "rectangle.stack",
                    message: mode == .mine ? "或点击右上角新建" : "从左侧浏览市场结果"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var manageColumn: some View {
        if let selected {
            ServiceCardDesignManagePane(card: selected)
        } else {
            NWDetailPlaceholder(title: "选择服务卡", systemImage: "rectangle.stack", message: "从左侧选择")
        }
    }

    @ViewBuilder
    private var publicPreviewColumn: some View {
        if let selected {
            ServiceCardCustomerPreviewPane(card: selected)
        } else {
            NWDetailPlaceholder(title: "客户预览", systemImage: "eye", message: "选择服务卡查看公开样式")
        }
    }

    private func previewListRow(_ card: ServiceCardDTO) -> some View {
        let isSelected = selected?.id == card.id
        return Button {
            selected = card
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title).font(.system(size: 13, weight: .semibold))
                HStack(spacing: 4) {
                    Circle().fill(statusDot(card.status)).frame(width: 6, height: 6)
                    Text(statusLabel(card.status)).font(.caption).foregroundStyle(.secondary)
                }
                Text("¥6,000 - ¥20,000 · 远程 / 现场 · 5天起")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("更新于 2024/05/20")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .nwSelectionChrome(isSelected: isSelected, cornerRadius: 0)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func statusDot(_ status: String?) -> Color {
        switch status?.uppercased() {
        case "PUBLISHED": AppTheme.openStatus
        case "DRAFT": AppTheme.urgent
        default: AppTheme.secondaryLabel
        }
    }

    private func statusLabel(_ status: String?) -> String {
        switch status?.uppercased() {
        case "PUBLISHED": "已上架"
        case "DRAFT": "草稿"
        default: "已下架"
        }
    }

    private func load() async {
        if let previewCards {
            cards = previewCards
            selected = selected ?? previewCards.first
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            switch mode {
            case .mine:
                cards = try await session.serviceCardService.mine()
            case .market:
                cards = try await session.serviceCardService.search(
                    keyword: marketKeyword.trimmingCharacters(in: .whitespacesAndNewlines),
                    limit: 40
                )
            }
            if let selected, cards.contains(where: { $0.id == selected.id }) { return }
            self.selected = cards.first
        } catch {
            cards = []
            selected = nil
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

enum ServiceCardsDesignPreviewFixtures {
    static let cards: [ServiceCardDTO] = [
        ServiceCardDTO(
            id: "preview-card-1",
            title: "产品策略与用户研究",
            summary: "从用户洞察到产品机会的系统化服务",
            description: "面向创业团队与产品部门，提供从用户研究、需求洞察到产品策略规划的一体化服务。交付包含研究报告、机会分析与路线图建议。",
            category: "产品策略",
            serviceType: "HYBRID",
            status: "PUBLISHED",
            tags: ["产品策略", "用户研究", "市场分析", "需求洞察", "产品规划"],
            priceMin: FlexibleDecimal(6_000),
            priceMax: FlexibleDecimal(20_000),
            publisher: AccountDesignPreviewFixtures.users.first
        ),
        ServiceCardDTO(id: "preview-card-2", title: "用户访谈与洞察报告", summary: "访谈提纲、执行与结构化洞察", description: "适合产品早期验证与迭代研究。", category: "用户研究", serviceType: "ONLINE", status: "DRAFT", tags: ["用户访谈", "研究报告"], priceMin: FlexibleDecimal(500), priceMax: FlexibleDecimal(900), publisher: AccountDesignPreviewFixtures.users.dropFirst().first),
        ServiceCardDTO(id: "preview-card-3", title: "产品文档结构优化", summary: "让复杂信息更清晰易读", description: "梳理层级、统一术语并改善阅读节奏。", category: "内容设计", serviceType: "ONLINE", status: "PUBLISHED", tags: ["文档", "信息架构"], priceMin: FlexibleDecimal(300), priceMax: FlexibleDecimal(600), publisher: AccountDesignPreviewFixtures.users.last)
    ]
}

private struct ServiceCardDesignManagePane: View {
    let card: ServiceCardDTO

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(card.title).font(.title2.bold())
                    NWStatusChip(text: "已上架", tint: AppTheme.openStatus)
                    Spacer()
                    Button("下架") {}.buttonStyle(.bordered)
                    Button("编辑") {}.buttonStyle(.borderedProminent)
                }
                Text(card.description ?? card.summary ?? "")
                    .foregroundStyle(.secondary)
                if let tags = card.tags {
                    FlowLayoutTags(tags: tags)
                }
                gridRow("价格区间", "¥6,000 - ¥20,000")
                gridRow("服务方式", "远程 / 现场")
                gridRow("交付方式", "文档报告 / 线上汇报 / 工作坊")
                gridRow("周期", "5天起")
                gridRow("接单能力", "每月可接 2 个项目")
                Text("资质说明").font(.headline).padding(.top, 8)
                Text("• 5 年以上产品策略与用户研究经验\n• 服务过多家消费电子产品团队")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(AppTheme.horizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppTheme.workspaceBackground)
    }

    private func gridRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
            Text(value).font(.caption)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct ServiceCardCustomerPreviewPane: View {
    let card: ServiceCardDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("客户看到的服务卡")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.softPrimary)
                    .frame(height: 80)
                    .overlay {
                        Image("NinewoodLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                    }
                Text(card.title).font(.title3.bold())
                Text("¥6,000 起").font(.headline)
                if let tags = card.tags?.prefix(3) {
                    HStack {
                        ForEach(Array(tags), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .overlay { Capsule().strokeBorder(AppTheme.outlineVariant) }
                        }
                    }
                }
                Text(String((card.description ?? "").prefix(80)) + "…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                NWPrimaryCTA(title: "查看详情")
            }
            .padding(16)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.outlineVariant) }
            .padding(.horizontal, 16)

            Text("* 实际展示以客户端为准")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 16)
            Spacer()
        }
        .frame(width: 280)
        .background(AppTheme.workspaceBackground)
    }
}

private struct FlowLayoutTags: View {
    let tags: [String]

    var body: some View {
        HStack {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.fill.opacity(0.35), in: Capsule())
            }
        }
    }
}

private struct ServiceCardDetailPane: View {
    let card: ServiceCardDTO
    var onChanged: () -> Void
    @Environment(AppSession.self) private var session
    @State private var message: String?
    @State private var showEdit = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(card.title).font(.title.bold())
                if let status = card.status { NWStatusChip(text: status) }
                Text(card.description ?? card.summary ?? "")
                    .foregroundStyle(.secondary)
                if let tags = card.tags, !tags.isEmpty {
                    Text(tags.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("编辑") { showEdit = true }
                    if (card.status ?? "").uppercased() != "PUBLISHED" {
                        Button("发布") { Task { await publish() } }.buttonStyle(.borderedProminent)
                    } else {
                        Button("下架") { Task { await unpublish() } }
                    }
                }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(AppTheme.horizontalPadding)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .background(AppTheme.workspaceBackground)
        .sheet(isPresented: $showEdit) {
            ServiceCardEditorSheet(card: card) {
                onChanged()
            }
            .frame(minWidth: 520, minHeight: 480)
        }
    }

    private func publish() async {
        do {
            _ = try await session.serviceCardService.publish(id: card.id)
            message = "已发布"
            onChanged()
        } catch {
            message = error.localizedDescription
        }
    }

    private func unpublish() async {
        do {
            _ = try await session.serviceCardService.unpublish(id: card.id)
            message = "已下架"
            onChanged()
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct ServiceCardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    var card: ServiceCardDTO?
    var onSaved: () -> Void

    @State private var title = ""
    @State private var summary = ""
    @State private var description = ""
    @State private var category = "日常服务"
    @State private var priceMin = ""
    @State private var isSaving = false
    @State private var error: String?

    private var isEditing: Bool { card != nil }

    init(card: ServiceCardDTO? = nil, onSaved: @escaping () -> Void) {
        self.card = card
        self.onSaved = onSaved
        if let card {
            _title = State(initialValue: card.title)
            _summary = State(initialValue: card.summary ?? "")
            _description = State(initialValue: card.description ?? "")
            _category = State(initialValue: card.category ?? "日常服务")
            if let min = card.priceMin?.value {
                _priceMin = State(initialValue: "\(min)")
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isEditing ? "编辑服务卡" : "新建服务卡").font(.title2.bold())
            TextField("标题", text: $title).textFieldStyle(.roundedBorder)
            TextField("摘要", text: $summary).textFieldStyle(.roundedBorder)
            TextEditor(text: $description).frame(minHeight: 100).padding(8).background(AppTheme.fill).clipShape(RoundedRectangle(cornerRadius: 8))
            TextField("分类", text: $category).textFieldStyle(.roundedBorder)
            TextField("最低价（可选）", text: $priceMin).textFieldStyle(.roundedBorder)
            if let error { Text(error).foregroundStyle(AppTheme.error).font(.caption) }
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button(isEditing ? "保存" : "创建") { Task { await save() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.isEmpty || description.isEmpty || isSaving)
            }
        }
        .padding(24)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let body = ServiceCardInputBody(
            title: title,
            summary: summary.isEmpty ? nil : summary,
            description: description,
            category: category,
            serviceType: "OFFLINE",
            tags: nil,
            priceMin: Double(priceMin),
            priceMax: nil,
            deliveryMode: "ONSITE",
            availability: "AVAILABLE"
        )
        do {
            if let card {
                _ = try await session.serviceCardService.update(id: card.id, body)
            } else {
                _ = try await session.serviceCardService.create(body)
            }
            onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
