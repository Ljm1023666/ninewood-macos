import SwiftUI

/// 服务卡独立工作区：字段编辑 → 结构化预览确认 → 创建草稿（可选再上架）。
struct CreateServiceCardView: View {
    @Environment(AppSession.self) private var session
    var embedded: Bool = true
    var frontendPreview: Bool = false

    @State private var draft = ServiceCardDraft()
    @State private var claimInput = ""
    @State private var phase: Phase = .edit
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var createdCardID: String?

    private enum Phase {
        case edit
        case confirm
    }

    private let serviceTypes: [(id: String, label: String)] = [
        ("ONLINE", "线上"),
        ("OFFLINE", "线下"),
        ("HYBRID", "线上+线下"),
    ]

    private let deliveryModes: [(id: String, label: String)] = [
        ("REMOTE", "远程交付"),
        ("ONSITE", "现场交付"),
        ("HYBRID", "远程 / 现场"),
    ]

    var body: some View {
        DocumentShell(maxWidth: 1100) {
            VStack(alignment: .leading, spacing: AppTheme.space16) {
                header
                if phase == .edit {
                    editLayout
                } else {
                    confirmLayout
                }
            }
        }
        .onAppear { consumeHandoff() }
        .alert("提示", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Button {
                        _ = session.navigation.navigate(to: "/publish")
                    } label: {
                        Label("发布工作台", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    Text("服务卡工作区")
                        .font(.system(size: 22, weight: .bold))
                }
                Text("左侧用 AI 整理服务字段，确认页核对后再创建草稿。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let successMessage {
                Text(successMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.openStatus)
            }
        }
    }

    private var editLayout: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: AppTheme.space16) {
                PublishAIOrganizePanel(
                    mode: .service,
                    frontendPreview: frontendPreview
                ) { result in
                    PublishDraftAIMapper.apply(result, to: &draft)
                }
                .frame(width: 320)
                .frame(minHeight: 420)

                formColumn.frame(maxWidth: .infinity)
                livePreview.frame(width: 280)
            }
            VStack(alignment: .leading, spacing: AppTheme.space16) {
                PublishAIOrganizePanel(
                    mode: .service,
                    frontendPreview: frontendPreview
                ) { result in
                    PublishDraftAIMapper.apply(result, to: &draft)
                }
                .frame(minHeight: 260)
                formColumn
            }
        }
    }

    private var formColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            fieldBlock("服务标题") {
                TextField("例如：周末上门家电清洗", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
            }
            fieldBlock("简介") {
                TextField("一句话说明你能提供什么", text: $draft.summary)
                    .textFieldStyle(.roundedBorder)
            }
            fieldBlock("服务说明") {
                TextEditor(text: $draft.description)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(AppTheme.fill.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }
            fieldBlock("类别") {
                TextField("例如：家电维修 / 设计 / 陪诊", text: $draft.category)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(alignment: .top, spacing: 16) {
                fieldBlock("服务方式") {
                    Picker("", selection: $draft.serviceType) {
                        ForEach(serviceTypes, id: \.id) { Text($0.label).tag($0.id) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                fieldBlock("交付方式") {
                    Picker("", selection: $draft.deliveryMode) {
                        ForEach(deliveryModes, id: \.id) { Text($0.label).tag($0.id) }
                    }
                    .labelsHidden()
                }
            }

            HStack(spacing: 12) {
                fieldBlock("最低报价") {
                    TextField("可选", text: $draft.priceMinText)
                        .textFieldStyle(.roundedBorder)
                }
                fieldBlock("最高报价") {
                    TextField("可选", text: $draft.priceMaxText)
                        .textFieldStyle(.roundedBorder)
                }
                fieldBlock("报价单位") {
                    TextField("次 / 小时 / 天", text: $draft.priceUnit)
                        .textFieldStyle(.roundedBorder)
                }
            }

            fieldBlock("能力声明") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("例如：持证上岗、同城 2 小时响应", text: $claimInput)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addClaim() }
                        Button("添加") { addClaim() }
                            .disabled(claimInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if !draft.claims.isEmpty {
                        FlowClaimChips(claims: draft.claims) { claim in
                            draft.claims.removeAll { $0 == claim }
                        }
                    }
                }
            }

            HStack {
                Button("返回选择") {
                    _ = session.navigation.navigate(to: "/publish")
                }
                Spacer()
                Button("预览并确认") {
                    do {
                        _ = try draft.publishCommand()
                        phase = .confirm
                    } catch {
                        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!draft.hasRequiredContent || isSaving)
            }
        }
    }

    private var livePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("卡片预览")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            previewCard
            Text("下一步将进入结构化确认，不会立刻提交。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var confirmLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("发布前确认")
                .font(.title3.bold())
            Text("请核对以下结构化信息。确认后才会创建服务卡草稿；上架需再次在「我的 → 服务卡」操作。")
                .font(.callout)
                .foregroundStyle(.secondary)

            previewCard

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                confirmRow("标题", draft.title)
                confirmRow("简介", draft.summary.isEmpty ? "—" : draft.summary)
                confirmRow("说明", draft.description)
                confirmRow("类别", draft.category)
                confirmRow("服务方式", label(for: draft.serviceType, in: serviceTypes))
                confirmRow("交付方式", label(for: draft.deliveryMode, in: deliveryModes))
                confirmRow("报价", priceSummary)
                confirmRow("能力声明", draft.claims.isEmpty ? "—" : draft.claims.joined(separator: " · "))
            }
            .padding(16)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.outlineVariant) }

            HStack {
                Button("返回修改") { phase = .edit }
                Spacer()
                Button(frontendPreview ? "预览：确认创建草稿" : "确认创建草稿") {
                    Task { await submit() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(draft.title.isEmpty ? "服务标题" : draft.title)
                .font(.headline)
            Text(draft.summary.isEmpty ? "简介将显示在这里" : draft.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(priceSummary)
                .font(.subheadline.weight(.semibold))
            Text("\(label(for: draft.serviceType, in: serviceTypes)) · \(label(for: draft.deliveryMode, in: deliveryModes))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if !draft.claims.isEmpty {
                Text(draft.claims.prefix(3).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.outlineVariant) }
    }

    private var priceSummary: String {
        let min = draft.priceMinText.trimmingCharacters(in: .whitespacesAndNewlines)
        let max = draft.priceMaxText.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = draft.priceUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        let unitSuffix = unit.isEmpty ? "" : "/\(unit)"
        if min.isEmpty, max.isEmpty { return "报价面议" }
        if !min.isEmpty, !max.isEmpty { return "¥\(min) – ¥\(max)\(unitSuffix)" }
        if !min.isEmpty { return "¥\(min) 起\(unitSuffix)" }
        return "最高 ¥\(max)\(unitSuffix)"
    }

    private func fieldBlock<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func confirmRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
        }
    }

    private func label(for id: String, in pairs: [(id: String, label: String)]) -> String {
        pairs.first(where: { $0.id == id })?.label ?? id
    }

    private func addClaim() {
        let text = claimInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if !draft.claims.contains(text) {
            draft.claims.append(text)
        }
        claimInput = ""
    }

    private func consumeHandoff() {
        guard let handoff = session.consumePublishHandoff(), handoff.kind == .service else { return }
        draft.applyPrefill(
            title: handoff.title.isEmpty ? nil : handoff.title,
            summary: handoff.summary.isEmpty ? nil : handoff.summary,
            description: handoff.description.isEmpty ? nil : handoff.description,
            category: handoff.category.isEmpty ? nil : handoff.category,
            serviceType: handoff.serviceType.isEmpty ? nil : handoff.serviceType,
            deliveryMode: handoff.deliveryMode.isEmpty ? nil : handoff.deliveryMode,
            priceMin: handoff.budgetMin.isEmpty ? nil : handoff.budgetMin,
            priceMax: handoff.budgetMax.isEmpty ? nil : handoff.budgetMax,
            priceUnit: handoff.priceUnit.isEmpty ? nil : handoff.priceUnit,
            claims: handoff.claims.isEmpty ? nil : handoff.claims
        )
    }

    private func submit() async {
        if frontendPreview {
            successMessage = "预览模式：已模拟创建草稿"
            phase = .edit
            draft.resetPublishedContent()
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let command = try draft.publishCommand()
            let body = ServiceCardInputBody(
                title: command.title,
                summary: command.summary,
                description: command.description,
                category: command.category,
                serviceType: command.serviceType,
                tags: command.tags.isEmpty ? nil : command.tags,
                priceMin: command.priceMin.map { NSDecimalNumber(decimal: $0).doubleValue },
                priceMax: command.priceMax.map { NSDecimalNumber(decimal: $0).doubleValue },
                deliveryMode: command.deliveryMode,
                availability: "AVAILABLE"
            )
            let card = try await session.serviceCardService.create(body)
            createdCardID = card.id
            successMessage = "已创建服务卡草稿，可在「我的 → 服务卡」上架"
            phase = .edit
            draft.resetPublishedContent()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct FlowClaimChips: View {
    let claims: [String]
    var onRemove: (String) -> Void

    var body: some View {
        FlexibleChipWrap {
            ForEach(claims, id: \.self) { claim in
                HStack(spacing: 4) {
                    Text(claim).font(.caption)
                    Button {
                        onRemove(claim)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.fill.opacity(0.4), in: Capsule())
            }
        }
    }
}

/// 简单横向换行容器（能力声明 chips）。
private struct FlexibleChipWrap<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        // macOS 15+ Layout; fallback to wrapping HStack via ViewThatFits not needed —
        // use LazyVGrid single flexible flow approximation.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
            content()
        }
    }
}
