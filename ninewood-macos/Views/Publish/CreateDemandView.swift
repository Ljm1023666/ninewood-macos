import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct CreateDemandView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session

    /// 嵌入主壳时不显示取消按钮，发布成功后清空表单
    var embedded: Bool = false
    var initialTitle: String = ""
    var initialOutcome: String = ""

    @State private var title = ""
    @State private var expectedOutcome = ""
    @State private var minPrice = "200"
    @State private var expectedPrice = ""
    @State private var timeLimitMinutes = 180
    @State private var applicantLimit = 10
    @State private var selectedTags: Set<String> = []
    @State private var availableTags: [TagDTO] = []
    @State private var regions: [RegionDTO] = []
    @State private var selectedRegionId: Int?
    @State private var allowNearby = true
    @State private var certifiedOnly = false
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

    private var canPublish: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !expectedOutcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isPublishing
            && (!allowNearby || selectedRegionId != nil)
    }

    var body: some View {
        DocumentShell(maxWidth: AppTheme.documentWideMaxWidth) {
            VStack(alignment: .leading, spacing: AppTheme.space24) {
                section("需求信息") {
                    VStack(spacing: 0) {
                        TextField("需求标题（例如：电脑清灰维护）", text: $title)
                            .textFieldStyle(.roundedBorder)
                            .padding(AppTheme.space12)
                        Divider()
                        TextEditor(text: $expectedOutcome)
                            .font(.body)
                            .frame(minHeight: 120)
                            .padding(AppTheme.space8)
                        if showOutcomeError {
                            Text("请填写期望效果")
                                .font(.caption)
                                .foregroundStyle(AppTheme.error)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, AppTheme.space12)
                                .padding(.bottom, AppTheme.space8)
                        }
                    }
                    .ninewoodCard()
                }

                section("报价") {
                    VStack(spacing: 12) {
                        moneyRow("最低保障金额", text: $minPrice)
                        moneyRow("预计成交金额（可选）", text: $expectedPrice)
                    }
                    .padding(16)
                    .ninewoodCard()
                }

                section("时间与人数") {
                    VStack(spacing: 12) {
                        Picker("完成时限", selection: $timeLimitMinutes) {
                            Text("1 小时").tag(60)
                            Text("3 小时").tag(180)
                            Text("今天内").tag(720)
                            Text("24 小时").tag(1_440)
                            Text("3 天").tag(4_320)
                        }
                        Stepper("申请者上限：\(applicantLimit)", value: $applicantLimit, in: 1...50)
                    }
                    .padding(16)
                    .ninewoodCard()
                }

                section("标签") {
                    VStack(alignment: .leading, spacing: 12) {
                        if isLoadingMeta && availableTags.isEmpty {
                            ProgressView().controlSize(.small)
                        } else if availableTags.isEmpty {
                            Text("暂无可用标签")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            FlowTagPicker(tags: availableTags.map(\.name), selection: $selectedTags)
                        }
                        if !selectedTags.isEmpty {
                            Text("已选：\(selectedTags.sorted().joined(separator: "、"))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .ninewoodCard()
                }

                section("附件图片") {
                    VStack(alignment: .leading, spacing: 12) {
                        PhotosPicker(
                            selection: $photoItems,
                            maxSelectionCount: 4,
                            matching: .images
                        ) {
                            Label(
                                isLoadingPhotos ? "读取中…" : "添加图片（最多 4 张）",
                                systemImage: "photo.on.rectangle.angled"
                            )
                        }
                        .disabled(isLoadingPhotos)
                        .onChange(of: photoItems) { _, items in
                            Task { await loadPhotos(items) }
                        }

                        if attachmentNames.isEmpty {
                            Text("可选：补充现场照片或参考图")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(attachmentNames.enumerated()), id: \.offset) { index, name in
                                HStack {
                                    Image(systemName: "photo")
                                        .foregroundStyle(AppTheme.primary)
                                    Text(name).font(.caption)
                                    Spacer()
                                    Button("移除") {
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
                                    .font(.caption)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .ninewoodCard()
                }

                section("位置与资格") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("允许附近的人发现（线下）", isOn: $allowNearby)
                        if allowNearby {
                            Picker("服务地区", selection: $selectedRegionId) {
                                Text("请选择地区").tag(Optional<Int>.none)
                                ForEach(regions) { region in
                                    Text(region.name ?? "地区 \(region.id)").tag(Optional(region.id))
                                }
                            }
                            if selectedRegionId == nil {
                                Text("线下需求需选择地区")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.error)
                            }
                        }
                        Toggle("仅认证服务者可申请", isOn: $certifiedOnly)
                    }
                    .padding(16)
                    .ninewoodCard()
                }

                Text("发布时需将最低保障 \(minPrice.isEmpty ? "0" : minPrice) 点预付至平台托管")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await attemptPublish() }
                } label: {
                    Group {
                        if isPublishing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("确认并发布")
                        }
                    }
                    .frame(maxWidth: 280)
                    .frame(height: 36)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canPublish)

                if publishSuccess {
                    Text("发布成功")
                        .foregroundStyle(AppTheme.openStatus)
                }
            }
        }
        .navigationTitle("发布需求")
        .toolbar {
            if !embedded {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .onAppear {
            if title.isEmpty, !initialTitle.isEmpty { title = initialTitle }
            if expectedOutcome.isEmpty, !initialOutcome.isEmpty { expectedOutcome = initialOutcome }
        }
        .task { await loadMeta() }
        .alert("发布失败", isPresented: Binding(
            get: { publishError != nil },
            set: { if !$0 { publishError = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(publishError ?? "")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func moneyRow(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
                .multilineTextAlignment(.trailing)
            Text("点").foregroundStyle(.secondary)
        }
    }

    private func loadMeta() async {
        isLoadingMeta = true
        defer { isLoadingMeta = false }
        async let tagsTask = session.tagService.list()
        async let regionsTask = session.regionService.children()
        availableTags = (try? await tagsTask) ?? []
        regions = (try? await regionsTask) ?? []
    }

    private func attemptPublish() async {
        showOutcomeError = expectedOutcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard canPublish else { return }
        guard let price = Decimal(string: minPrice), price > 0 else {
            publishError = "请填写有效的最低保障金额"
            return
        }
        if allowNearby && selectedRegionId == nil {
            publishError = "线下需求请选择服务地区"
            return
        }
        isPublishing = true
        publishSuccess = false
        defer { isPublishing = false }
        let tagList = Array(selectedTags).sorted()
        do {
            _ = try await session.demandService.createDemand(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: expectedOutcome.trimmingCharacters(in: .whitespacesAndNewlines),
                expectedOutcome: expectedOutcome.trimmingCharacters(in: .whitespacesAndNewlines),
                minPrice: price,
                expectedPrice: expectedPrice.isEmpty ? nil : Decimal(string: expectedPrice),
                category: tagList.first ?? "日常服务",
                serviceType: allowNearby ? "OFFLINE" : "ONLINE",
                maxApplicants: applicantLimit,
                isCertifiedOnly: certifiedOnly,
                tags: tagList,
                regionId: allowNearby ? selectedRegionId : nil,
                timeLimitMinutes: timeLimitMinutes,
                files: attachmentFiles,
                idempotencyKey: publishIdempotencyKey
            )
            publishIdempotencyKey = UUID().uuidString
            if embedded {
                title = ""
                expectedOutcome = ""
                selectedTags = []
                selectedRegionId = nil
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
