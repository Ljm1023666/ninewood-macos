import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct CreateDemandView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session

    /// 嵌入主壳时不显示取消按钮，发布成功后清空表单
    var embedded: Bool = false
    /// Reference-page mode: all choices and feedback are local fixture state.
    var frontendPreview: Bool = false
    var initialTitle: String = ""
    var initialOutcome: String = ""

    @State private var draft = DemandDraft()
    @State private var detailedDescription = ""
    @State private var deadlineDate = Calendar.current.date(
        from: DateComponents(year: 2025, month: 6, day: 15)
    ) ?? Date()
    @State private var availableTags: [TagDTO] = []
    @State private var regions: [RegionDTO] = []
    @State private var showOutcomeError = false
    @State private var isPublishing = false
    @State private var publishError: String?
    @State private var publishSuccess = false
    @State private var publishIdempotencyKey = UUID().uuidString
    @State private var isLoadingMeta = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var attachmentFiles: [MultipartFile] = []
    @State private var attachmentNames: [String] = []
    @State private var isLoadingPhotos = false
    /// Design rendering separates「服务人数」stepper from preview「申请人数上限」.
    @State private var serviceHeadcount = 1

    private var canPublish: Bool {
        draft.hasRequiredContent && !isPublishing
    }

    private var step1Complete: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.expectedOutcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var step2Complete: Bool {
        !draft.allowsNearbyDiscovery || draft.selectedRegionID != nil
    }

    private var step3Ready: Bool { draft.hasRequiredContent }

    private var titleValid: Bool {
        let count = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).count
        return count >= 5 && count <= 60
    }

    private var outcomeValid: Bool {
        let count = draft.expectedOutcome.trimmingCharacters(in: .whitespacesAndNewlines).count
        return count >= 5 && count <= 80
    }

    private var descriptionValid: Bool {
        let count = detailedDescription.trimmingCharacters(in: .whitespacesAndNewlines).count
        return count >= 10 && count <= 2_000
    }

    var body: some View {
        DocumentShell(maxWidth: 1280) {
            VStack(alignment: .leading, spacing: AppTheme.space16) {
                pageHeader
                publishSteps

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: AppTheme.space16) {
                        PublishAIOrganizePanel(
                            mode: .demand,
                            frontendPreview: frontendPreview
                        ) { result in
                            PublishDraftAIMapper.apply(
                                result,
                                to: &draft,
                                detailedDescription: &detailedDescription
                            )
                        }
                        .frame(width: 320)
                        .frame(minHeight: 420)

                        publishForm
                            .frame(maxWidth: .infinity)
                        publishPreview
                            .frame(width: 260)
                    }

                    VStack(alignment: .leading, spacing: AppTheme.space16) {
                        PublishAIOrganizePanel(
                            mode: .demand,
                            frontendPreview: frontendPreview
                        ) { result in
                            PublishDraftAIMapper.apply(
                                result,
                                to: &draft,
                                detailedDescription: &detailedDescription
                            )
                        }
                        .frame(minHeight: 280)
                        publishForm
                    }
                }
            }
        }
        .navigationTitle(embedded ? "" : "发布需求")
        .toolbar {
            if !embedded {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .onAppear {
            draft.applyInitialContent(title: initialTitle, expectedOutcome: initialOutcome)
            consumePublishHandoff()
        }
        .task {
            if frontendPreview {
                applyDesignPreviewFixtures()
            } else {
                await loadMeta()
            }
        }
        .alert("发布失败", isPresented: Binding(
            get: { publishError != nil },
            set: { if !$0 { publishError = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(publishError ?? "")
        }
    }

    // MARK: - Header / steps

    private var pageHeader: some View {
        HStack(alignment: .center) {
            if embedded {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Button {
                            _ = session.navigation.navigate(to: "/publish")
                        } label: {
                            Label("发布工作台", systemImage: "chevron.left")
                        }
                        .buttonStyle(.borderless)
                        Text("需求卡工作区")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(AppTheme.onSurface)
                    }
                    Text("左侧用 AI 整理字段，右侧核对后发布。助手不会静默提交。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if publishSuccess {
                Label("已发布", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.openStatus)
                    .font(.subheadline.weight(.semibold))
            }
            Button("保存草稿") {
                Task { await saveDraft() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(AppTheme.primary)
        }
    }

    private func consumePublishHandoff() {
        guard let handoff = session.consumePublishHandoff(), handoff.kind == .demand else { return }
        draft.applyInitialContent(
            title: handoff.title,
            expectedOutcome: handoff.expectedOutcome.isEmpty ? handoff.description : handoff.expectedOutcome
        )
        if detailedDescription.isEmpty, !handoff.description.isEmpty {
            detailedDescription = handoff.description
        }
        if draft.minimumPriceText == "200" || draft.minimumPriceText.isEmpty,
           !handoff.budgetMin.isEmpty {
            draft.minimumPriceText = handoff.budgetMin
        }
        if draft.expectedPriceText.isEmpty, !handoff.budgetMax.isEmpty {
            draft.expectedPriceText = handoff.budgetMax
        }
        if !handoff.serviceType.isEmpty {
            draft.allowsNearbyDiscovery = handoff.serviceType.uppercased() != "ONLINE"
        }
        if !handoff.category.isEmpty {
            draft.selectedTags.insert(handoff.category)
        }
    }

    private var publishSteps: some View {
        HStack(spacing: AppTheme.space12) {
            stepBadge(1, title: "需求信息", state: step1Complete ? .done : .current)
            stepConnector
            stepBadge(
                2,
                title: "服务范围",
                state: step2Complete ? .done : (step1Complete ? .current : .upcoming)
            )
            stepConnector
            stepBadge(
                3,
                title: "确认托管",
                state: step3Ready ? .done : (step1Complete && step2Complete ? .current : .upcoming)
            )
            Spacer()
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    private enum PublishStepState {
        case upcoming, current, done
    }

    private var stepConnector: some View {
        Image(systemName: "arrow.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppTheme.secondaryLabel)
    }

    private func stepBadge(_ number: Int, title: String, state: PublishStepState) -> some View {
        let active = state == .current || state == .done
        return HStack(spacing: 8) {
            ZStack {
                Text(state == .done ? "" : "\(number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(active ? .white : AppTheme.secondaryLabel)
                if state == .done {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 22, height: 22)
            .background(
                state == .done || state == .current ? AppTheme.primary : Color(red: 0.94, green: 0.95, blue: 0.96),
                in: Circle()
            )
            .overlay {
                if state == .upcoming {
                    Circle().strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                }
            }
            Text(title)
                .font(.subheadline.weight(state == .current ? .semibold : .regular))
                .foregroundStyle(active ? AppTheme.onSurface : .secondary)
        }
    }

    // MARK: - Form

    private var publishForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            countedTextField(
                label: "标题",
                required: true,
                text: $draft.title,
                placeholder: "清楚说明你需要完成的事情",
                maxCount: 60,
                showCheck: titleValid,
                singleLine: true
            )

            countedTextField(
                label: "期望效果",
                required: true,
                text: $draft.expectedOutcome,
                placeholder: "描述可验收的具体结果",
                maxCount: 80,
                showCheck: outcomeValid,
                singleLine: true
            )
            if showOutcomeError {
                Text("请填写期望效果")
                    .font(.caption)
                    .foregroundStyle(AppTheme.error)
            }

            countedTextEditor(
                label: "详细描述",
                required: true,
                text: $detailedDescription,
                maxCount: 2_000,
                showCheck: descriptionValid,
                minHeight: 118
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ],
                alignment: .leading,
                spacing: 16
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("最低保障金额", required: true)
                    moneyField($draft.minimumPriceText)
                    Text("发布时将全额托管")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("期望预算", required: false)
                    moneyField($draft.expectedPriceText)
                    Text("可协商")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                compactField("完成时限", required: true) {
                    deadlineField
                }
            }

            HStack(alignment: .top, spacing: 16) {
                compactField("申请人数上限", required: true) {
                    peopleStepper
                }
                .frame(maxWidth: 168)

                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("标签", required: true)
                    tagsField
                    Text("最多选择 5 个标签")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                .frame(maxWidth: .infinity)
            }

            HStack(alignment: .top, spacing: 16) {
                compactField("服务方式", required: true) {
                    Picker("", selection: Binding(
                        get: { draft.allowsNearbyDiscovery },
                        set: { draft.allowsNearbyDiscovery = $0 }
                    )) {
                        Text("线上").tag(false)
                        Text("线下").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                compactField("地区", required: draft.allowsNearbyDiscovery) {
                    regionPicker
                }
                .frame(maxWidth: .infinity)
            }

            compactField("图片附件", required: false) {
                attachmentDropzone
            }

            ForEach(Array(attachmentNames.enumerated()), id: \.offset) { index, name in
                HStack {
                    Label(name, systemImage: "photo")
                        .font(.caption)
                    Spacer()
                    Button("移除") { removeAttachment(at: index) }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.primary)
                }
            }

            HStack {
                Text("仅认证服务者可申请")
                    .font(.subheadline)
                Spacer()
                Toggle("", isOn: $draft.certifiedProvidersOnly)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(AppTheme.primary)
            }
            .padding(.top, 2)

            if publishSuccess {
                Text("草稿已保存在当前设备")
                    .font(.caption)
                    .foregroundStyle(AppTheme.openStatus)
            }
        }
        .padding(20)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
        }
    }

    private var deadlineField: some View {
        HStack(spacing: 8) {
            DatePicker(
                "",
                selection: $deadlineDate,
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            Spacer(minLength: 0)
            Image(systemName: "calendar")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(AppTheme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
        }
    }

    private var peopleStepper: some View {
        HStack(spacing: 0) {
            Button {
                if frontendPreview {
                    serviceHeadcount = max(1, serviceHeadcount - 1)
                } else {
                    draft.applicantLimit = max(1, draft.applicantLimit - 1)
                }
            } label: {
                Image(systemName: "minus")
                    .font(.caption.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Text("\(frontendPreview ? serviceHeadcount : draft.applicantLimit)")
                .font(.subheadline.monospacedDigit().weight(.medium))
                .frame(maxWidth: .infinity)

            Button {
                if frontendPreview {
                    serviceHeadcount = min(50, serviceHeadcount + 1)
                } else {
                    draft.applicantLimit = min(50, draft.applicantLimit + 1)
                }
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .frame(height: 34)
        .background(AppTheme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
        }
    }

    private var tagsField: some View {
        HStack(alignment: .center, spacing: 6) {
            if draft.selectedTags.isEmpty {
                Text(isLoadingMeta && availableTags.isEmpty ? "加载标签…" : "选择标签")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(draft.selectedTags.sorted(), id: \.self) { tag in
                        tagChip(tag)
                    }
                }
            }
            Spacer(minLength: 4)
            Menu {
                ForEach(availableTags, id: \.name) { tag in
                    Button {
                        if draft.selectedTags.contains(tag.name) {
                            draft.selectedTags.remove(tag.name)
                        } else if draft.selectedTags.count < 5 {
                            draft.selectedTags.insert(tag.name)
                        }
                    } label: {
                        HStack {
                            Text(tag.name)
                            if draft.selectedTags.contains(tag.name) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .disabled(availableTags.isEmpty && !isLoadingMeta)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minHeight: 34, alignment: .leading)
        .background(AppTheme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
        }
    }

    private func tagChip(_ name: String) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.caption)
            Button {
                draft.selectedTags.remove(name)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(AppTheme.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppTheme.softPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(AppTheme.primary.opacity(0.55), lineWidth: 1)
        }
    }

    private var regionPicker: some View {
        Picker("", selection: $draft.selectedRegionID) {
            if regions.isEmpty {
                Text("全国可服务").tag(Optional(0))
            }
            ForEach(regions) { region in
                Text(region.name ?? "地区 \(region.id)").tag(Optional(region.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(AppTheme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
        }
    }

    private var attachmentDropzone: some View {
        PhotosPicker(
            selection: $photoItems,
            maxSelectionCount: 5,
            matching: .images
        ) {
            VStack(spacing: 8) {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(AppTheme.primary)
                Text(isLoadingPhotos ? "读取中…" : "点击或拖拽文件到此处上传")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.onSurface)
                Text("支持 JPG、PNG、PDF，单文件不超过 10MB，最多 5 个")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(AppTheme.primary.opacity(0.03))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        AppTheme.primary.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.2, dash: [6, 4])
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoadingPhotos)
        .onChange(of: photoItems) { _, items in
            Task { await loadPhotos(items) }
        }
    }

    // MARK: - Preview

    private var publishPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("发布预览")
                .font(.headline)

            Divider()

            previewValue("标题", value: draft.title.isEmpty ? "尚未填写" : draft.title)
            previewValue(
                "期望效果",
                value: draft.expectedOutcome.isEmpty ? "尚未填写" : draft.expectedOutcome
            )

            Divider()

            previewMetaRow("可见时长", value: visibleDurationText)
            previewMetaRow("申请人数上限", value: "\(draft.applicantLimit)人")
            HStack {
                Text("服务方式")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(draft.allowsNearbyDiscovery ? "线下" : "线上")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.openStatus)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.openStatus.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(AppTheme.openStatus.opacity(0.55), lineWidth: 1)
                    }
            }

            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("发布时将全额托管 最低保障金额 \(draft.minimumPriceText.isEmpty ? "0" : draft.minimumPriceText) 点")
                        .font(.system(size: 12, weight: .semibold))
                    Text("资金由平台托管，完成后按约定释放给服务者。")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.error.opacity(0.85))
                }
            } icon: {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 16))
            }
            .foregroundStyle(AppTheme.error)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.error.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AppTheme.error.opacity(0.28), lineWidth: 1)
            }

            Button {
                Task { await attemptPublish() }
            } label: {
                Group {
                    if isPublishing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("确认并发布")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .foregroundStyle(canPublish ? Color.white : AppTheme.secondaryLabel)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    canPublish ? AppTheme.primary : AppTheme.fill,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canPublish)

            Button("存为草稿") {
                Task { await saveDraft() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(AppTheme.onSurface)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(red: 0.82, green: 0.84, blue: 0.86), lineWidth: 1)
            }

            Text("预计发布后，将收到合适服务者的申请。")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryLabel)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
        }
        .padding(18)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
        }
    }

    // MARK: - Field helpers

    private func fieldLabel(_ title: String, required: Bool) -> some View {
        HStack(spacing: 3) {
            if required {
                Text("*")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.error)
            }
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.onSurface)
        }
    }

    private func compactField<Content: View>(
        _ title: String,
        required: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(title, required: required)
            content()
        }
    }

    private func countedTextField(
        label: String,
        required: Bool,
        text: Binding<String>,
        placeholder: String,
        maxCount: Int,
        showCheck: Bool,
        singleLine: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(label, required: required)
            HStack(spacing: 8) {
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .lineLimit(singleLine ? 1 : 3)
                if showCheck {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.openStatus)
                        .font(.body)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(AppTheme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
            }
            HStack {
                Spacer()
                Text("\(min(text.wrappedValue.count, maxCount))/\(maxCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: text.wrappedValue) { _, newValue in
            if newValue.count > maxCount {
                text.wrappedValue = String(newValue.prefix(maxCount))
            }
        }
    }

    private func countedTextEditor(
        label: String,
        required: Bool,
        text: Binding<String>,
        maxCount: Int,
        showCheck: Bool,
        minHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                fieldLabel(label, required: required)
                Spacer()
                if showCheck {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.openStatus)
                        .font(.body)
                }
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: minHeight)
                    .padding(6)
                if text.wrappedValue.isEmpty {
                    Text("补充背景、交付物与验收标准")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Text("\(min(text.wrappedValue.count, maxCount))/\(maxCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
            }
        }
        .onChange(of: text.wrappedValue) { _, newValue in
            if newValue.count > maxCount {
                text.wrappedValue = String(newValue.prefix(maxCount))
            }
        }
    }

    private func moneyField(_ text: Binding<String>) -> some View {
        HStack(spacing: 6) {
            TextField("0", text: text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
            Text("点")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(AppTheme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
        }
    }

    private func previewValue(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .lineLimit(3)
                .foregroundStyle(AppTheme.onSurface)
        }
    }

    private func previewMetaRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.onSurface)
        }
    }

    private var visibleDurationText: String {
        if frontendPreview {
            return "15分钟"
        }
        switch draft.timeLimitMinutes {
        case 15: return "15分钟"
        case 60: return "1小时"
        case 180: return "3小时"
        case 720: return "今天内"
        case 1_440: return "24小时"
        case 4_320: return "3天"
        default: return "\(draft.timeLimitMinutes)分钟"
        }
    }

    // MARK: - Fixtures / actions

    private func applyDesignPreviewFixtures() {
        availableTags = [
            "用户研究", "定量研究", "定性研究", "智能硬件",
            "产品设计", "交互设计", "内容创作", "数据分析", "品牌设计"
        ].map { TagDTO(name: $0, category: nil) }
        regions = [
            RegionDTO(id: 0, name: "全国可服务", parentId: nil)
        ]

        // Character counts match rendering counters (16/60, 22/80, ~185/2000).
        draft.title = "智能硬件产品的用户研究与体验优化"
        draft.expectedOutcome = "形成可落地的用户洞察报告，并提供可执行的建议"
        detailedDescription = """
        面向智能硬件新品完成目标用户访谈与可用性走查：梳理核心任务路径与关键决策点，覆盖首次配对、日常使用与异常恢复场景；结合定量问卷与定性深访交叉验证，输出可落地的洞察报告，并给出体验优化优先级、验证方式与下一阶段迭代建议，附样本画像、问题清单、改版假设与验收标准，便于产品与设计团队直接执行落地并复盘；交付含方法说明、证据摘录、行动项清单与访谈提纲。
        """.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.minimumPriceText = "600"
        draft.expectedPriceText = "1200"
        draft.timeLimitMinutes = 15
        draft.applicantLimit = 20
        serviceHeadcount = 1
        draft.selectedTags = ["用户研究", "定量研究", "定性研究", "智能硬件"]
        draft.allowsNearbyDiscovery = false
        draft.selectedRegionID = 0
        draft.certifiedProvidersOnly = true
        deadlineDate = Calendar.current.date(
            from: DateComponents(year: 2025, month: 6, day: 15)
        ) ?? Date()
    }

    private func removeAttachment(at index: Int) {
        if attachmentFiles.indices.contains(index) {
            attachmentFiles.remove(at: index)
        }
        if attachmentNames.indices.contains(index) {
            attachmentNames.remove(at: index)
        }
        if photoItems.indices.contains(index) {
            photoItems.remove(at: index)
        }
    }

    private func messageDraftSaved() {
        publishSuccess = true
    }

    private func saveDraft() async {
        if frontendPreview {
            messageDraftSaved()
            return
        }
        let command: DemandPublishCommand
        do {
            command = try draft.publishCommand()
        } catch {
            // 草稿允许更宽松：至少要有标题
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                publishError = "请先填写标题再存草稿"
                return
            }
            do {
                _ = try await session.demandService.saveDraft(
                    title: title,
                    description: draft.expectedOutcome,
                    expectedOutcome: draft.expectedOutcome,
                    minPrice: Decimal(string: draft.minimumPriceText) ?? 200,
                    expectedPrice: Decimal(string: draft.expectedPriceText),
                    category: draft.selectedTags.sorted().first ?? "日常服务",
                    serviceType: draft.allowsNearbyDiscovery ? "OFFLINE" : "ONLINE",
                    maxApplicants: draft.applicantLimit,
                    isCertifiedOnly: draft.certifiedProvidersOnly,
                    tags: Array(draft.selectedTags).sorted(),
                    regionId: draft.selectedRegionID,
                    timeLimitMinutes: draft.timeLimitMinutes
                )
                messageDraftSaved()
            } catch {
                publishError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            return
        }
        do {
            try await session.demandPublishRepository.saveDraft(command)
            messageDraftSaved()
        } catch {
            publishError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadMeta() async {
        isLoadingMeta = true
        defer { isLoadingMeta = false }
        let metadata = await session.demandPublishRepository.loadMetadata()
        availableTags = metadata.tags
        regions = metadata.regions
    }

    private func attemptPublish() async {
        if frontendPreview {
            showOutcomeError = draft.expectedOutcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            publishSuccess = !showOutcomeError
            return
        }
        showOutcomeError = draft.expectedOutcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let command: DemandPublishCommand
        do {
            command = try draft.publishCommand()
        } catch {
            publishError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }
        isPublishing = true
        publishSuccess = false
        defer { isPublishing = false }
        do {
            try await session.demandPublishRepository.publish(
                command,
                files: attachmentFiles,
                idempotencyKey: publishIdempotencyKey
            )
            publishIdempotencyKey = UUID().uuidString
            if embedded {
                draft.resetPublishedContent()
                detailedDescription = ""
                photoItems = []
                attachmentFiles = []
                attachmentNames = []
                publishSuccess = true
            } else {
                dismiss()
            }
        } catch {
            publishError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        isLoadingPhotos = true
        defer { isLoadingPhotos = false }
        var files: [MultipartFile] = []
        var names: [String] = []
        for (index, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else { continue }
            let name = "photo_\(index + 1).jpg"
            files.append(
                MultipartFile(
                    fieldName: "files",
                    fileName: name,
                    mimeType: "image/jpeg",
                    data: data
                )
            )
            names.append(name)
        }
        attachmentFiles = files
        attachmentNames = names
    }
}

// MARK: - Flow layout for selected tag chips

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            width = max(width, x + size.width)
            x += size.width + spacing
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

/// 简单流式标签多选（macOS 列表友好）
struct FlowTagPicker: View {
    let tags: [String]
    @Binding var selection: Set<String>

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                let selected = selection.contains(tag)
                Button {
                    if selected { selection.remove(tag) } else { selection.insert(tag) }
                } label: {
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selected ? AppTheme.primary.opacity(0.15) : AppTheme.fill)
                        .foregroundStyle(selected ? AppTheme.primary : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(selected ? AppTheme.primary : AppTheme.outlineVariant, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
