import SwiftUI

struct CertCenterView: View {
    @Environment(AppSession.self) private var session
    @State private var status: CertStatusDTO?
    @State private var availableTags: [TagDTO] = []
    @State private var regions: [RegionDTO] = []
    @State private var selectedTags: Set<String> = []
    @State private var selectedRegionId: Int?
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var message: String?
    @State private var loadError: String?

    var body: some View {
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
                regionId: selectedRegionId
            )
            message = "认证申请已提交"
            status = try? await session.certificationService.status()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
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
