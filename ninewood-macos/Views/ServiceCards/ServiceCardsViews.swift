import SwiftUI

struct ServiceCardsManageView: View {
    @Environment(AppSession.self) private var session
    @State private var cards: [ServiceCardDTO] = []
    @State private var selected: ServiceCardDTO?
    @State private var showCreate = false
    @State private var message: String?
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                NWPaneCaption(text: "创建、发布你的服务能力")
                if isLoading && cards.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 32)
                    Spacer(minLength: 0)
                } else if let loadError, cards.isEmpty {
                    NWEmptyState(title: "服务卡加载失败", systemImage: "wifi.exclamationmark", message: loadError)
                    Spacer(minLength: 0)
                } else if cards.isEmpty {
                    NWEmptyState(title: "暂无服务卡", systemImage: "rectangle.stack", message: "创建一张服务卡，展示你的能力")
                    Spacer(minLength: 0)
                } else {
                    List(cards, selection: $selected) { card in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.title).font(.headline)
                            Text(card.summary ?? card.description ?? "")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            if let status = card.status {
                                NWStatusChip(text: status)
                            }
                        }
                        .tag(card)
                    }
                    .listStyle(.inset)
                }
            }
            .paneColumn(minWidth: 300, idealWidth: 340)

            Divider()

            Group {
                if let selected {
                    ServiceCardDetailPane(card: selected) {
                        Task { await load() }
                    }
                } else {
                    NWDetailPlaceholder(title: "选择服务卡", systemImage: "rectangle.stack", message: "或点击右上角新建")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("服务卡")
        .toolbar {
            Button("新建") { showCreate = true }
            Button("刷新") { Task { await load() } }
        }
        .task { await load() }
        .sheet(isPresented: $showCreate) {
            ServiceCardEditorSheet { Task { await load() } }
                .frame(minWidth: 520, minHeight: 480)
        }
        .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("确定", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            cards = try await session.serviceCardService.mine()
            if let selected, cards.contains(where: { $0.id == selected.id }) { return }
            self.selected = cards.first
        } catch {
            cards = []
            selected = nil
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
