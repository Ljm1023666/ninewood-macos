import AppKit
import SwiftUI
import PhotosUI

struct CertCenterView: View {
    @Environment(AppSession.self) private var session
    @State private var status: CertStatusDTO?
    @State private var availableTags: [TagDTO] = []
    @State private var regions: [RegionDTO] = []
    @State private var selectedTags: Set<String> = []
    @State private var selectedRegionId: Int?
    @State private var proofItems: [PhotosPickerItem] = []
    @State private var proofUrls: [String] = []
    @State private var proofNames: [String] = []
    @State private var isUploadingProof = false
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var message: String?
    @State private var loadError: String?
    private let previewStatus: CertStatusDTO?

    init(preview: Bool = false) {
        let status = preview ? CertStatusDTO(certificationLevel: "PRO", completedOrders: 23, snatchCredits: 8, creditScore: 86) : nil
        self.previewStatus = status
        _status = State(initialValue: status)
        _availableTags = State(initialValue: preview ? [
            TagDTO(name: "产品设计", category: "专业服务"),
            TagDTO(name: "用户研究", category: "专业服务"),
            TagDTO(name: "视觉设计", category: "创意服务"),
            TagDTO(name: "内容设计", category: "创意服务")
        ] : [])
        _regions = State(initialValue: preview ? [
            RegionDTO(id: 310000, name: "上海", parentId: nil),
            RegionDTO(id: 110000, name: "北京", parentId: nil),
            RegionDTO(id: 440300, name: "深圳", parentId: nil)
        ] : [])
        _selectedTags = State(initialValue: preview ? ["产品设计", "用户研究"] : [])
        _selectedRegionId = State(initialValue: preview ? 310000 : nil)
    }

    var body: some View {
        Group {
            if previewStatus != nil {
                CertReferencePreview()
            } else {
                DocumentShell(maxWidth: AppTheme.documentWideMaxWidth) {
                    VStack(alignment: .leading, spacing: AppTheme.space24) {
                        statusCard

                        VStack(alignment: .leading, spacing: AppTheme.space12) {
                            Text("申请 / 更新技能认证").font(.headline)
                            Text("选择擅长标签与服务地区后提交。认证通过后可接收带标签推送。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if availableTags.isEmpty && isLoading {
                                ProgressView()
                            } else {
                                FlowTagPicker(tags: availableTags.map(\.name), selection: $selectedTags)
                            }

                            Picker("服务地区", selection: $selectedRegionId) {
                                Text("可选").tag(Optional<Int>.none)
                                ForEach(regions) { region in
                                    Text(region.name ?? "\(region.id)").tag(Optional(region.id))
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("证明材料").font(.subheadline.weight(.semibold))
                                PhotosPicker(
                                    selection: $proofItems,
                                    maxSelectionCount: 6,
                                    matching: .images
                                ) {
                                    Label(
                                        isUploadingProof ? "上传中…" : "选择图片证明",
                                        systemImage: "paperclip"
                                    )
                                }
                                .disabled(isUploadingProof)
                                .onChange(of: proofItems) { _, items in
                                    Task { await uploadProofs(items) }
                                }
                                if !proofNames.isEmpty {
                                    ForEach(Array(proofNames.enumerated()), id: \.offset) { _, name in
                                        Text(name)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text("可选：上传作品集或资质截图，提交时一并附上。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            HStack(spacing: AppTheme.space12) {
                                Button {
                                    Task { await register() }
                                } label: {
                                    Text(isSubmitting ? "提交中…" : "提交认证申请")
                                        .frame(minWidth: 140)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(selectedTags.isEmpty || isSubmitting)

                                Button("尝试升级等级") {
                                    Task { await upgrade() }
                                }
                                .disabled(isSubmitting)
                            }
                        }
                        .padding(AppTheme.space16)
                        .ninewoodCard()

                        if let message {
                            Text(message)
                                .foregroundStyle(AppTheme.openStatus)
                        }
                    }
                }
            }
        }
        .navigationTitle("认证")
        .task { await load() }
        .alert("提示", isPresented: Binding(
            get: { loadError != nil },
            set: { if !$0 { loadError = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(loadError ?? "")
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("当前状态").font(.headline)
            if isLoading && status == nil {
                ProgressView().controlSize(.small)
            } else {
                HStack {
                    Text(status?.certificationLevel ?? session.currentUser?.certificationLevel ?? "NONE")
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.primary)
                    Spacer()
                    Text("信用 \(status?.creditScore ?? session.currentUser?.creditScore ?? 60)")
                        .foregroundStyle(.secondary)
                }
                Text("完成订单 \(status?.completedOrders ?? session.currentUser?.completedOrders ?? 0) · 抢单额度 \(status?.snatchCredits ?? 0)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .ninewoodCard()
    }

    private func load() async {
        if let previewStatus {
            status = previewStatus
            return
        }
        isLoading = true
        defer { isLoading = false }
        async let statusTask = session.certificationService.status()
        async let tagsTask = session.tagService.list()
        async let regionsTask = session.regionService.children()
        status = try? await statusTask
        availableTags = (try? await tagsTask) ?? []
        regions = (try? await regionsTask) ?? []
    }

    private func register() async {
        isSubmitting = true
        message = nil
        defer { isSubmitting = false }
        do {
            try await session.certificationService.register(
                tags: Array(selectedTags).sorted(),
                regionId: selectedRegionId,
                proofUrls: proofUrls.isEmpty ? nil : proofUrls
            )
            message = "认证申请已提交"
            status = try? await session.certificationService.status()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func uploadProofs(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isUploadingProof = true
        defer { isUploadingProof = false }
        var urls: [String] = []
        var names: [String] = []
        for (index, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else { continue }
            let file = MultipartFile(
                fieldName: "file",
                fileName: "proof_\(index + 1).jpg",
                mimeType: "image/jpeg",
                data: data
            )
            do {
                let url = try await session.certificationService.uploadProof(file: file)
                urls.append(url)
                names.append(file.fileName)
            } catch {
                loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        proofUrls = urls
        proofNames = names
    }

    private func upgrade() async {
        isSubmitting = true
        message = nil
        defer { isSubmitting = false }
        do {
            try await session.certificationService.upgrade()
            message = "已提交升级"
            status = try? await session.certificationService.status()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Design preview (10)

private struct CertReferencePreview: View {
    @State private var skillTags = ["用户研究", "产品设计", "数据分析"]
    @State private var materialsExpanded = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 16) {
                        profileCard
                        materialsCard
                        privacyFooter
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 14) {
                        requirementCard
                        reviewCard
                    }
                    .frame(width: 268)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 1080)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.documentBackground)
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                CertAvatar(name: "林间有风", asset: "AvatarLinXia", size: 72)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("林间有风")
                            .font(.system(size: 20, weight: .bold))
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.primary)
                        Text("L3 已认证")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.primary, in: Capsule(style: .continuous))
                    }

                    HStack(spacing: 28) {
                        metric("86", "信用分")
                        metric("23", "完成订单")
                        metric("4", "抢单信用")
                    }
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("距离 L4 还需 14 分")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.secondaryLabel)
                    Spacer()
                    Text("86 / 100")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppTheme.fill.opacity(0.7))
                        Capsule()
                            .fill(AppTheme.openStatus)
                            .frame(width: max(8, geo.size.width * 0.86))
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(20)
        .ninewoodCard()
    }

    private var materialsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("认证资料")
                .font(.system(size: 17, weight: .bold))
                .padding(.bottom, 4)

            formRow(
                title: "技能标签",
                detail: "选择你擅长的领域（最多 5 个）"
            ) {
                HStack(spacing: 8) {
                    ForEach(skillTags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                                .font(.system(size: 12, weight: .medium))
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(AppTheme.onSurface)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.surfaceLow, in: Capsule(style: .continuous))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                        }
                    }
                    Button {} label: {
                        Text("+ 添加")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(AppTheme.primary.opacity(0.45), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            formRow(
                title: "服务模式",
                detail: "你更擅长的合作方式"
            ) {
                dropdownChip("远程为主，可线下配合")
            }

            formRow(
                title: "服务区域",
                detail: "可接受服务的地区范围"
            ) {
                HStack(spacing: 8) {
                    dropdownChip("中国大陆")
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        materialsExpanded.toggle()
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("证明资料")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.onSurface)
                            Text("上传能证明你能力的材料")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.secondaryLabel)
                        }
                        Spacer()
                        Text("已上传 3 份")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Image(systemName: materialsExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                }
                .buttonStyle(.plain)

                if materialsExpanded {
                    HStack(alignment: .top, spacing: 10) {
                        uploadFile(title: "作品集_用户研究案例.pdf", size: "2.4 MB", icon: "doc.fill", tint: AppTheme.primary)
                        uploadFile(title: "产品设计作品集.pdf", size: "3.1 MB", icon: "doc.fill", tint: AppTheme.primary)
                        uploadFile(title: "数据分析项目报告.png", size: "1.8 MB", icon: "photo", tint: AppTheme.openStatus)
                        uploadPlaceholder
                    }
                }
            }
            .padding(.vertical, 16)

            Divider()

            formRow(
                title: "隐私设置",
                detail: "设置谁可以查看你的认证资料",
                showDivider: false
            ) {
                dropdownChip("所有人可见（公开展示认证等级与技能）")
            }
        }
        .padding(20)
        .ninewoodCard()
    }

    private var privacyFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondaryLabel)
            Text("你的资料仅用于认证审核，不会泄露给未授权的第三方。")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondaryLabel)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private var requirementCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("下一等级要求（L4）")
                .font(.system(size: 15, weight: .semibold))

            requirement(title: "信用分 ≥ 100 分", value: "86 / 100", state: .short)
            requirement(title: "完成订单 ≥ 30 单", value: "23 / 30", state: .short)
            requirement(title: "抢单信用 ≥ 6 分", value: "4 / 6", state: .short)
            requirement(title: "至少 5 份好评", value: "已满足", state: .met)
            requirement(title: "通过平台能力审核", value: "未开始", state: .pending)
        }
        .padding(16)
        .ninewoodCard()
    }

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("审核进度")
                .font(.system(size: 15, weight: .semibold))

            reviewRow(label: "当前状态", value: "资料待更新", valueColor: AppTheme.urgent)
            reviewRow(label: "上次提交", value: "--")
            reviewRow(label: "预计完成时间", value: "--")

            Text("更新资料后可重新申请升级审核。完善证明材料有助于提升通过率。")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)

            Button {} label: {
                Text("更新认证资料")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {} label: {
                Text("申请升级")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(AppTheme.primary, lineWidth: 1.2)
                            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    )
            }
            .buttonStyle(.plain)

            Button {} label: {
                Text("认证有疑问？查看帮助文档")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.primary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(16)
        .ninewoodCard()
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondaryLabel)
        }
    }

    private func formRow<Content: View>(
        title: String,
        detail: String,
        showDivider: Bool = true,
        @ViewBuilder trailing: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                .frame(minWidth: 140, alignment: .leading)
                Spacer(minLength: 8)
                trailing()
            }
            .padding(.vertical, 14)

            if showDivider {
                Divider()
            }
        }
    }

    private func dropdownChip(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryLabel)
        }
        .foregroundStyle(AppTheme.onSurface)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.surfaceLow, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
        }
    }

    private func uploadFile(title: String, size: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.onSurface)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(size)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.secondaryLabel)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
        }
    }

    private var uploadPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.primary)
            Text("上传文件")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.onSurface)
            Text("支持 PDF、图片\n(≤10MB)")
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 108)
        .background(AppTheme.surfaceLow.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppTheme.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        }
    }

    private enum RequirementState {
        case short
        case met
        case pending
    }

    private func requirementIcon(_ state: RequirementState) -> String {
        switch state {
        case .met: "checkmark.circle.fill"
        case .pending: "clock"
        case .short: "circle"
        }
    }

    private func requirement(title: String, value: String, state: RequirementState) -> some View {
        HStack(spacing: 8) {
            Image(systemName: requirementIcon(state))
                .font(.system(size: 13))
                .foregroundStyle(
                    state == .met ? AppTheme.openStatus
                        : state == .pending ? AppTheme.secondaryLabel
                        : AppTheme.outlineVariant
                )
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.onSurface)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(valueColor(state))
        }
        .padding(.vertical, 4)
    }

    private func valueColor(_ state: RequirementState) -> Color {
        switch state {
        case .short: AppTheme.error
        case .met: AppTheme.openStatus
        case .pending: AppTheme.secondaryLabel
        }
    }

    private func reviewRow(label: String, value: String, valueColor: Color = AppTheme.onSurface) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.secondaryLabel)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(valueColor)
        }
    }
}

private struct CertAvatar: View {
    let name: String
    let asset: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let asset, NSImage(named: asset) != nil {
                Image(asset)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(AppTheme.fill.opacity(0.7))
                    .overlay {
                        Text(String(name.prefix(1)))
                            .font(.system(size: size * 0.38, weight: .semibold))
                            .foregroundStyle(AppTheme.primary)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(AppTheme.outlineVariant.opacity(0.5), lineWidth: 0.5)
        }
    }
}
