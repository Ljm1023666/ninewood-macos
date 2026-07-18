import SwiftUI

struct NaturalLoopWorkspaceView: View {
    @Environment(AppSession.self) private var session

    @State private var query = ""
    @State private var runCollection: NaturalLoopRunCollection?
    @State private var recommendations: NaturalLoopRecommendations?
    @State private var selectedOffering: NaturalLoopOffering?
    @State private var selectedRunID: String?
    @State private var selectedRun: NaturalLoopRun?
    @State private var offeringExecution: NaturalLoopExecution?
    @State private var isLoadingInbox = false
    @State private var isSearching = false
    @State private var isRunningOffering = false
    @State private var isLoadingDetail = false
    @State private var inboxError: String?
    @State private var searchError: String?
    @State private var offeringRunError: String?
    @State private var showHumanDraft = false
    @State private var showAgentSheet = false
    @State private var showCapabilityCatalog = false
    @State private var detailError: String?
    private let previewCollection: NaturalLoopRunCollection?

    init(previewCollection: NaturalLoopRunCollection? = nil) {
        self.previewCollection = previewCollection
        _query = State(initialValue: previewCollection == nil ? "" : "整理一次用户研究并验证交付结果")
        _runCollection = State(initialValue: previewCollection)
        _selectedRunID = State(initialValue: previewCollection?.runs.first?.id)
        _selectedRun = State(initialValue: previewCollection?.runs.first)
    }

    var body: some View {
        Group {
            if previewCollection != nil {
                NaturalLoopReferencePreview()
            } else {
                liveWorkspace
            }
        }
        .navigationTitle("自然回")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCapabilityCatalog = true
                } label: {
                    Label("系统能力", systemImage: "bolt.horizontal.circle")
                }
                .help("查看系统自动验证能力及在线状态")
            }
        }
        .sheet(isPresented: $showCapabilityCatalog) {
            HeavenCapabilityCatalogView()
                .environment(session)
                .frame(minWidth: 620, minHeight: 520)
        }
        .sheet(isPresented: $showHumanDraft) {
            CreateDemandView(
                embedded: false,
                frontendPreview: false,
                initialTitle: humanDraftTitle,
                initialOutcome: humanDraftOutcome
            )
            .environment(session)
            .frame(minWidth: 720, minHeight: 640)
        }
        .sheet(isPresented: $showAgentSheet) {
            AgentChatView(initialPrompt: query.isEmpty ? nil : query)
                .environment(session)
                .frame(minWidth: 880, minHeight: 640)
        }
        .task {
            guard previewCollection == nil else { return }
            await loadInbox()
        }
    }

    private var liveWorkspace: some View {
        VStack(spacing: 0) {
            intentBar
            Divider()
            HStack(spacing: 0) {
                inboxList
                    .frame(width: 280)
                Divider()
                detailPane
                    .frame(maxWidth: .infinity)
            }
        }
        .background(AppTheme.documentBackground)
    }

    private var humanDraftTitle: String {
        if let fallback = recommendations?.humanFallback?.title { return fallback }
        if let run = selectedRun {
            return run.offering?.loop.title ?? run.definition?.name ?? query
        }
        return query
    }

    private var humanDraftOutcome: String {
        if let fallback = recommendations?.humanFallback?.description { return fallback }
        if let run = selectedRun {
            return run.offering?.loop.summary ?? run.definition?.description ?? query
        }
        return query
    }

    // MARK: - Intent (top bar)

    private var intentBar: some View {
        VStack(alignment: .leading, spacing: AppTheme.space8) {
            HStack(alignment: .top, spacing: AppTheme.space12) {
                TextField("现在想完成什么？例如：找到附近可协作的人", text: $query, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.plain)
                    .padding(AppTheme.space12)
                    .background(AppTheme.fill.opacity(0.55), in: RoundedRectangle(cornerRadius: AppTheme.buttonRadius, style: .continuous))

                VStack(spacing: AppTheme.space8) {
                    Button {
                        Task { await searchIntent() }
                    } label: {
                        Label(isSearching ? "理解中…" : "生成路径", systemImage: "sparkles")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSearching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        showAgentSheet = true
                    } label: {
                        Label("助手", systemImage: "bubble.left.and.sparkles")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.bordered)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if let searchError {
                Text(searchError)
                    .font(.caption)
                    .foregroundStyle(AppTheme.error)
            }

            if let recommendations {
                recommendationStrip(recommendations)
            }
        }
        .padding(AppTheme.space16)
        .background(AppTheme.workspaceBackground)
    }

    private func recommendationStrip(_ recommendations: NaturalLoopRecommendations) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.space8) {
            HStack {
                Text("推荐路径")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("清除") {
                    self.recommendations = nil
                    selectedOffering = nil
                    offeringExecution = nil
                    offeringRunError = nil
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.space8) {
                    ForEach(recommendations.items) { item in
                        Button {
                            selectedOffering = item.offering
                            offeringExecution = nil
                            offeringRunError = nil
                            selectedRunID = nil
                            selectedRun = nil
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(item.offering.loop.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    NWStatusChip(
                                        text: NaturalLoopPresentation.boundaryTitle(item.offering.loop.boundaryKind),
                                        tint: NaturalLoopPresentation.boundaryTint(item.offering.loop.boundaryKind)
                                    )
                                }
                                Text(item.offering.loop.summary ?? "执行路径")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .frame(width: 200, alignment: .leading)
                            }
                            .padding(AppTheme.space12)
                            .frame(width: 220, alignment: .leading)
                            .background(
                                selectedOffering?.id == item.offering.id ? AppTheme.softPrimary : AppTheme.surface,
                                in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                                    .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if let fallback = recommendations.humanFallback {
                        Button { showHumanDraft = true } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(fallback.title, systemImage: "person.2.fill")
                                    .font(.subheadline.weight(.semibold))
                                Text(fallback.description ?? "转成人协作")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(AppTheme.space12)
                            .frame(width: 200, alignment: .leading)
                            .ninewoodCard()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Inbox list

    private var inboxList: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryRow
                .padding(.horizontal, AppTheme.space16)
                .padding(.top, AppTheme.space12)
                .padding(.bottom, AppTheme.space8)

            HStack {
                Text("进行中")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if isLoadingInbox {
                    ProgressView().controlSize(.small)
                }
                Button("刷新") { Task { await loadInbox() } }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            .padding(.horizontal, AppTheme.space16)
            .padding(.bottom, AppTheme.space8)

            if let inboxError, runCollection?.runs.isEmpty != false {
                NWEmptyState(title: "无法加载自然回", systemImage: "wifi.exclamationmark", message: inboxError)
                Spacer(minLength: 0)
            } else if let runCollection, runCollection.runs.isEmpty {
                NWEmptyState(
                    title: "还没有自然回",
                    systemImage: "arrow.triangle.2.circlepath",
                    message: "在上方输入目标后，新的自然回会出现在这里。"
                )
                Spacer(minLength: 0)
            } else {
                List(selection: $selectedRunID) {
                    ForEach(runCollection?.runs ?? []) { run in
                        NaturalLoopRunRow(run: run, selected: selectedRunID == run.id)
                            .tag(run.id)
                            .listRowInsets(EdgeInsets(
                                top: 6,
                                leading: AppTheme.space12,
                                bottom: 6,
                                trailing: AppTheme.space12
                            ))
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .onChange(of: selectedRunID) { _, newValue in
                    guard let newValue else { return }
                    selectedOffering = nil
                    Task { await loadDetail(newValue) }
                }
            }
        }
    }

    private var summaryRow: some View {
        let summary = runCollection?.summary
        return HStack(spacing: AppTheme.space8) {
            summaryChip("总数", "\(summary?.total ?? 0)")
            summaryChip("进行中", "\(summary?.active ?? 0)")
            summaryChip("完成", "\(summary?.succeeded ?? 0)")
            summaryChip("成功率", summary?.successRate.map(percent) ?? "—")
        }
    }

    private func summaryChip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.space8)
        .padding(.vertical, 6)
        .background(AppTheme.fill.opacity(0.45), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPane: some View {
        if let selectedOffering {
            ScrollView {
                inlineOfferingPanel(selectedOffering)
                    .padding(AppTheme.space24)
                    .frame(maxWidth: 640, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AppTheme.workspaceBackground)
        } else {
            NaturalLoopRunDetailPane(
                run: selectedRun,
                isLoading: isLoadingDetail,
                error: detailError,
                onRefresh: { id in await refreshDetailQuietly(id) },
                onRetryVerification: { id in await retryVerification(id) },
                onHumanCollaboration: { showHumanDraft = true }
            )
        }
    }

    @ViewBuilder
    private func inlineOfferingPanel(_ offering: NaturalLoopOffering) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.space16) {
            Text("确认执行路径")
                .font(.title2.bold())

            Text(offering.loop.title)
                .font(.title3.weight(.semibold))
            Text(offering.loop.summary ?? "确认后将启动自然回，并由系统验证结果。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let offeringRunError {
                Text(offeringRunError)
                    .font(.caption)
                    .foregroundStyle(AppTheme.error)
            }

            if let offeringExecution {
                VStack(alignment: .leading, spacing: AppTheme.space8) {
                    HStack {
                        Text(offeringExecution.isPreview ? "已生成预览" : "自然回已启动")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        NWStatusChip(text: NaturalLoopPresentation.stageTitle(offeringExecution.stage))
                    }
                    Text(NaturalLoopPresentation.executionSummary(offeringExecution))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(AppTheme.space12)
                .background(AppTheme.fill.opacity(0.5), in: RoundedRectangle(cornerRadius: AppTheme.buttonRadius, style: .continuous))
            }

            HStack(spacing: AppTheme.space12) {
                Button {
                    Task { await runSelectedOffering(offering) }
                } label: {
                    Label(isRunningOffering ? "正在运行…" : "确认运行", systemImage: isRunningOffering ? "hourglass" : "play.fill")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunningOffering)

                Button("取消") {
                    selectedOffering = nil
                    offeringExecution = nil
                    offeringRunError = nil
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Data

    private func loadInbox(selecting runID: String? = nil) async {
        if let previewCollection {
            runCollection = previewCollection
            selectedRunID = runID ?? selectedRunID ?? previewCollection.runs.first?.id
            selectedRun = previewCollection.runs.first { $0.id == selectedRunID }
            inboxError = nil
            return
        }
        isLoadingInbox = true
        defer { isLoadingInbox = false }
        do {
            let value = try await session.naturalLoopRepository.mine()
            runCollection = value
            if let runID {
                selectedRunID = runID
            } else {
                selectedRunID = selectedRunID ?? value.runs.first?.id
            }
            inboxError = nil
            if let selectedRunID {
                await loadDetail(selectedRunID)
            }
        } catch {
            inboxError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func searchIntent() async {
        isSearching = true
        defer { isSearching = false }
        do {
            recommendations = try await session.naturalLoopRepository.recommend(query: query)
            selectedOffering = nil
            offeringExecution = nil
            offeringRunError = nil
            searchError = nil
        } catch {
            searchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func runSelectedOffering(_ offering: NaturalLoopOffering) async {
        isRunningOffering = true
        offeringRunError = nil
        offeringExecution = nil
        defer { isRunningOffering = false }
        do {
            let result = try await session.naturalLoopRepository.run(offeringID: offering.id)
            offeringExecution = result
            if let runID = result.runID, !runID.isEmpty {
                recommendations = nil
                selectedOffering = nil
                await loadInbox(selecting: runID)
            } else {
                offeringRunError = NaturalLoopPresentation.executionSummary(result)
            }
        } catch {
            offeringRunError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadDetail(_ id: String) async {
        if let previewCollection {
            selectedRun = previewCollection.runs.first { $0.id == id }
            detailError = nil
            return
        }
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        do {
            selectedRun = try await session.naturalLoopRepository.detail(id: id)
            detailError = nil
        } catch {
            detailError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @discardableResult
    private func refreshDetailQuietly(_ id: String) async -> Bool {
        do {
            selectedRun = try await session.naturalLoopRepository.detail(id: id)
            detailError = nil
            return true
        } catch let error as APIError {
            detailError = error.errorDescription
            if case .rateLimited = error { return false }
            return false
        } catch {
            detailError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private func retryVerification(_ id: String) async {
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        do {
            selectedRun = try await session.naturalLoopRepository.retryVerification(runID: id)
            detailError = nil
            await loadInbox(selecting: id)
        } catch {
            detailError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

private struct NaturalLoopReferencePreview: View {
    private struct OfferingItem: Identifiable {
        let id: Int
        let title: String
        let detail: String
        let icon: String
        let available: Bool
    }

    private struct RecentRun: Identifiable {
        let id: Int
        let title: String
        let detail: String
        let status: NaturalLoopPresentation.DesignRunStatus
        let time: String
    }

    private struct TimelineEvent: Identifiable {
        let id: Int
        let time: String
        let actor: NaturalLoopPresentation.LoopActor
        let text: String
    }

    @State private var selectedOffering = 0
    @State private var selectedRecentRun = 0
    @State private var search = ""
    @State private var url = "https://sspai.com/post/92406"
    @State private var note = "提取文章标题、作者、发布时间、正文内容、所有图片及图注（如有）、以及文章标签。"
    @State private var showCapabilityCatalog = false

    private let offerings: [OfferingItem] = [
        .init(id: 0, title: "网页内容提取", detail: "提取网页正文、标题、图片等", icon: "globe", available: true),
        .init(id: 1, title: "文档结构化", detail: "将文档转为结构化数据", icon: "doc.text", available: true),
        .init(id: 2, title: "信息核验", detail: "核验事实与来源可信度", icon: "checkmark.shield", available: true),
        .init(id: 3, title: "新闻摘要", detail: "生成新闻要点摘要", icon: "list.bullet.rectangle", available: true),
        .init(id: 4, title: "公司信息查询", detail: "查询公司基本信息", icon: "building.2", available: true),
        .init(id: 5, title: "产品对比分析", detail: "对比产品参数与口碑", icon: "scalemass", available: false)
    ]

    private let recentRuns: [RecentRun] = [
        .init(id: 0, title: "网页内容提取", detail: "https://sspai.com/post/92406", status: .succeeded, time: "今天 14:32"),
        .init(id: 1, title: "信息核验", detail: "中国空间站建成时间", status: .succeeded, time: "今天 11:18"),
        .init(id: 2, title: "文档结构化", detail: "产品需求文档.pdf", status: .succeeded, time: "昨天 17:42"),
        .init(id: 3, title: "网页内容提取", detail: "https://www.gov.cn/zhengce/", status: .running, time: "昨天 16:05")
    ]

    private let timeline: [TimelineEvent] = [
        .init(id: 0, time: "14:32:11", actor: .human, text: "HUMAN 提交请求"),
        .init(id: 1, time: "14:32:12", actor: .earth, text: "EARTH 开始执行"),
        .init(id: 2, time: "14:32:18", actor: .earth, text: "EARTH 提取完成"),
        .init(id: 3, time: "14:32:24", actor: .heaven, text: "HEAVEN 开始核验"),
        .init(id: 4, time: "14:32:30", actor: .heaven, text: "HEAVEN 核验通过")
    ]

    private var currentOffering: OfferingItem {
        offerings.first(where: { $0.id == selectedOffering }) ?? offerings[0]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button {
                    showCapabilityCatalog = true
                } label: {
                    Text("系统能力")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.onSurface)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color(red: 0.82, green: 0.84, blue: 0.86), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                Button {} label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .frame(width: 28, height: 28)
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color(red: 0.82, green: 0.84, blue: 0.86), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(AppTheme.surface)
            Divider()

            HStack(spacing: 0) {
                offeringPane
                    .frame(width: 240)
                Divider()
                executionPane
                    .frame(width: 400)
                Divider()
                resultPane
                    .frame(maxWidth: .infinity)
            }
        }
        .background(AppTheme.surface)
        .sheet(isPresented: $showCapabilityCatalog) {
            HeavenCapabilityCatalogView()
                .frame(minWidth: 620, minHeight: 520)
        }
    }

    // MARK: - Offering list

    private var offeringPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("选择一个回")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 10)

            NWSearchBar(text: $search, placeholder: "搜索回或关键词")
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredOfferings) { item in
                        Button {
                            selectedOffering = item.id
                        } label: {
                            offeringCard(item, selected: item.id == selectedOffering)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }

            Text("共 12 个回")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Divider() }
        }
        .background(AppTheme.surface)
    }

    private var filteredOfferings: [OfferingItem] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return offerings }
        return offerings.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.detail.localizedCaseInsensitiveContains(q)
        }
    }

    private func offeringCard(_ item: OfferingItem, selected: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 32, height: 32)
                .background(
                    selected ? AppTheme.softPrimary : AppTheme.surfaceLow,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.onSurface)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    NWStatusChip(text: NaturalLoopPresentation.actorTitle(.earth))
                    NWStatusChip(
                        text: NaturalLoopPresentation.actorTitle(.heaven),
                        tint: NaturalLoopPresentation.actorTint(.heaven)
                    )
                }

                Text(item.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                    Text(NaturalLoopPresentation.availabilityTitle(available: item.available))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(NaturalLoopPresentation.availabilityTint(available: item.available))
            }
        }
        .padding(10)
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
                    selected ? AppTheme.primary.opacity(0.45) : Color.clear,
                    lineWidth: 1
                )
        }
    }

    // MARK: - Execution / form

    private var executionPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: currentOffering.icon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(AppTheme.primary)
                        .frame(width: 48, height: 48)
                        .background(AppTheme.softPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(currentOffering.title)
                            .font(.system(size: 20, weight: .bold))
                        HStack(spacing: 6) {
                            NWStatusChip(text: NaturalLoopPresentation.actorTitle(.earth))
                            NWStatusChip(
                                text: NaturalLoopPresentation.actorTitle(.heaven),
                                tint: NaturalLoopPresentation.actorTint(.heaven)
                            )
                        }
                    }
                }
                .padding(.bottom, 12)

                Text("由 EARTH 访问网页并提取内容，由 HEAVEN 核验来源与一致性，返回可信的结构化结果。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 18)

                Text("目标网页 URL *")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.bottom, 6)

                HStack(spacing: 8) {
                    TextField("https://", text: $url)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    if !url.isEmpty {
                        Button {
                            url = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                }
                .padding(.bottom, 14)

                HStack {
                    Text("提取说明（可选）")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(note.count)/500")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 6)

                TextEditor(text: $note)
                    .font(.system(size: 13))
                    .frame(minHeight: 96, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                    }
                    .padding(.bottom, 10)

                Label("我们仅在本次运行中访问该链接，不会保存或用于训练。", systemImage: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 14)

                Button {} label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("运行")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 18)

                Divider()
                    .padding(.bottom, 14)

                Text("最近运行")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.bottom, 10)

                VStack(spacing: 0) {
                    ForEach(recentRuns) { run in
                        Button {
                            selectedRecentRun = run.id
                        } label: {
                            recentRunRow(run, selected: run.id == selectedRecentRun)
                        }
                        .buttonStyle(.plain)
                        if run.id != recentRuns.last?.id {
                            Divider().padding(.leading, 4)
                        }
                    }
                }

                Button {} label: {
                    HStack(spacing: 4) {
                        Text("查看全部运行记录")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.primary)
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .background(AppTheme.surface)
    }

    private func recentRunRow(_ run: RecentRun, selected: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(run.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.onSurface)
                Text(run.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Label(
                NaturalLoopPresentation.designRunStatusTitle(run.status),
                systemImage: NaturalLoopPresentation.designRunStatusSymbol(run.status)
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(NaturalLoopPresentation.designRunStatusTint(run.status))
            .labelStyle(.titleAndIcon)

            Text(run.time)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 72, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(
            selected ? AppTheme.surfaceLow.opacity(0.85) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    // MARK: - Result / detail

    private var resultPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("最新运行详情")
                            .font(.system(size: 15, weight: .semibold))
                        Text("网页内容提取 · 今天 14:32（用时 18.7 秒）")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    NWStatusChip(text: "成功", tint: AppTheme.openStatus)
                    Button {} label: {
                        Label("重试核验", systemImage: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.bottom, 16)

                processMap
                    .padding(.bottom, 4)

                resultSection("输入摘要") {
                    summaryRow("目标 URL", url.isEmpty ? "—" : url, valueAccent: true)
                    summaryRow("提取说明", note.isEmpty ? "—" : note)
                }

                resultSection("EARTH 执行结果") {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.openStatus)
                        Text("提取成功")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.openStatus)
                    }
                    .padding(.bottom, 8)

                    extractedField("标题", "少数派的编辑们最近买了这些产品")
                    extractedField("作者", "Matrix")
                    extractedField("发布时间", "2024-05-20 10:00")
                    extractedField("正文", "……（共 8,642 字）")
                    extractedField("图片", "12 张")
                    extractedField("标签", "购买指南、数码、编辑推荐")

                    Button {} label: {
                        HStack(spacing: 4) {
                            Text("查看完整结果")
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.primary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }

                resultSection("HEAVEN 核验结果") {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.openStatus)
                        Text("核验通过")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.openStatus)
                    }
                    .padding(.bottom, 8)

                    checkRow("来源可访问")
                    checkRow("内容与来源一致")
                    checkRow("未发现敏感或违规内容")
                }

                resultSection("证据时间线", showDivider: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(timeline) { event in
                            timelineRow(event, isLast: event.id == timeline.last?.id)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .background(AppTheme.surface)
    }

    private var processMap: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                processNode(.human)
                processConnector
                processNode(.earth)
                processConnector
                processNode(.heaven)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(AppTheme.surfaceLow.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
            }
        }
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func processNode(_ actor: NaturalLoopPresentation.LoopActor) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(NaturalLoopPresentation.actorTint(actor).opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(NaturalLoopPresentation.actorTint(actor))
            }
            Text(NaturalLoopPresentation.actorTitle(actor))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppTheme.onSurface)
            Text(NaturalLoopPresentation.actorCaption(actor))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var processConnector: some View {
        Rectangle()
            .fill(AppTheme.primary.opacity(0.55))
            .frame(width: 36, height: 2)
            .padding(.bottom, 28)
    }

    private func resultSection<Content: View>(
        _ title: String,
        showDivider: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            content()
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            if showDivider { Divider() }
        }
    }

    private func summaryRow(_ label: String, _ value: String, valueAccent: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(valueAccent ? AppTheme.primary : AppTheme.onSurface)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func extractedField(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(label)：")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.onSurface)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private func checkRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppTheme.openStatus)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.onSurface)
        }
        .padding(.vertical, 3)
    }

    private func timelineRow(_ event: TimelineEvent, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle()
                    .fill(NaturalLoopPresentation.actorTint(event.actor))
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)
                if !isLast {
                    Rectangle()
                        .fill(AppTheme.outlineVariant)
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 8)

            Text(event.time)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)

            Text(event.text)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, isLast ? 0 : 10)
        .fixedSize(horizontal: false, vertical: true)
    }
}

enum NaturalLoopDesignPreviewFixtures {
    static let definition = NaturalLoopDefinition(
        code: "research-delivery",
        name: "研究交付验证",
        description: "从研究输入到结构化洞察，并核验交付证据。",
        executionMode: "ASSISTED"
    )

    static let runs: [NaturalLoopRun] = [
        run("01", .executing, 0.68, "用户访谈洞察整理", Date().addingTimeInterval(-3_600)),
        run("02", .verifying, 0.9, "品牌视觉交付核验", Date().addingTimeInterval(-7_200)),
        run("03", .succeeded, 1, "竞品体验报告", Date().addingTimeInterval(-86_400)),
        run("04", .waitingHuman, 0.42, "线下服务范围确认", Date().addingTimeInterval(-172_800))
    ]

    static let collection = NaturalLoopRunCollection(
        runs: runs,
        summary: NaturalLoopRunSummary(total: 4, active: 3, succeeded: 1, failed: 0, successRate: 0.92)
    )

    private static func run(
        _ id: String,
        _ stage: NaturalLoopStage,
        _ progress: Double,
        _ title: String,
        _ createdAt: Date
    ) -> NaturalLoopRun {
        let loop = NaturalLoop(
            id: "preview-loop-\(id)",
            title: title,
            summary: "自动整理关键输入、生成结果并记录可复验的过程证据。",
            boundaryKind: id == "04" ? .human : .earth,
            definition: definition,
            paths: ["输入", "执行", "验证"],
            requiresVerification: true
        )
        let offering = NaturalLoopOffering(id: "preview-offering-\(id)", loop: loop, executionMode: "ASSISTED")
        return NaturalLoopRun(
            id: "preview-run-\(id)",
            boundaryKind: loop.boundaryKind,
            stage: stage,
            progress: progress,
            definition: definition,
            offering: offering,
            context: LoopContext(
                initiatorReference: "林夏",
                receiverReference: "九木系统",
                demandID: "preview-\(id)",
                orderID: nil,
                parentRunID: nil,
                correlationID: "NW-\(id)",
                input: .object(["目标": .string(title)]),
                expectedOutcome: .string("形成可验收结果"),
                actualOutcome: stage == .succeeded ? .string("结果已核验") : nil
            ),
            evidence: [
                LoopEvidence(id: "preview-evidence-\(id)", type: "RESULT_SNAPSHOT", actorReference: "system", visibility: "MEMBERS", payload: .string("已记录阶段结果"), createdAt: createdAt.addingTimeInterval(1_200))
            ],
            interventions: [],
            links: [],
            startedAt: createdAt,
            completedAt: stage.isTerminal ? createdAt.addingTimeInterval(3_600) : nil,
            createdAt: createdAt
        )
    }
}

private struct HeavenCapabilityCatalogView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var capabilities: [HeavenCapabilityDTO] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && capabilities.isEmpty {
                    ProgressView("加载系统能力…")
                } else if let errorMessage, capabilities.isEmpty {
                    NWEmptyState(
                        title: "能力目录加载失败",
                        systemImage: "wifi.exclamationmark",
                        message: errorMessage
                    )
                } else if capabilities.isEmpty {
                    NWEmptyState(
                        title: "暂无系统能力",
                        systemImage: "bolt.horizontal.circle",
                        message: "服务端当前未公开可浏览的自动能力"
                    )
                } else {
                    List(capabilities) { capability in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(capability.title)
                                    .font(.headline)
                                Spacer()
                                NWStatusChip(
                                    text: capability.status ?? "UNKNOWN",
                                    tint: statusTint(capability.status)
                                )
                            }
                            if let summary = capability.summary, !summary.isEmpty {
                                Text(summary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 12) {
                                if let code = capability.definitionCode {
                                    Text(code)
                                }
                                if let runCount = capability.runCount {
                                    Text("运行 \(runCount)")
                                }
                                if let successCount = capability.successCount {
                                    Text("成功 \(successCount)")
                                }
                                if let failCount = capability.failCount, failCount > 0 {
                                    Text("失败 \(failCount)")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("系统自动能力")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("刷新") { Task { await load() } }
                        .disabled(isLoading)
                }
            }
            .task { await load() }
        }
    }

    private func statusTint(_ status: String?) -> Color {
        switch status?.uppercased() {
        case "ONLINE", "ACTIVE", "AVAILABLE":
            AppTheme.openStatus
        case "DEGRADED", "PARTIAL":
            AppTheme.urgent
        default:
            .secondary
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            capabilities = try await session.loopService.heavenCapabilities()
        } catch {
            capabilities = []
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

private struct NaturalLoopRunRow: View {
    let run: NaturalLoopRun
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 4)
                NWStatusChip(
                    text: NaturalLoopPresentation.boundaryTitle(run.boundaryKind),
                    tint: NaturalLoopPresentation.boundaryTint(run.boundaryKind)
                )
            }
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(NaturalLoopPresentation.stageTitle(run.stage, style: .workspace))
                .font(.caption.weight(.medium))
            Text(progressText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .opacity(selected ? 1 : 1)
    }

    private var title: String {
        run.offering?.loop.title ?? run.definition?.name ?? "自然回"
    }

    private var summary: String {
        run.offering?.loop.summary ?? run.definition?.description ?? "从意图到结果的协作单元"
    }

    private var progressText: String {
        if let progress = run.progress {
            "完成度 \(Int((progress * 100).rounded()))%"
        } else {
            "状态：\(NaturalLoopPresentation.stageTitle(run.stage, style: .workspace))"
        }
    }
}

struct NaturalLoopRunDetailPane: View {
    let run: NaturalLoopRun?
    let isLoading: Bool
    let error: String?
    var onRefresh: (String) async -> Bool = { _ in true }
    var onRetryVerification: (String) async -> Void = { _ in }
    var onHumanCollaboration: (() -> Void)? = nil

    @State private var isRetrying = false
    @State private var retryMessage: String?
    @State private var pollTask: Task<Void, Never>?
    @State private var pollingPausedMessage: String?

    private var canRetry: Bool {
        guard let run else { return false }
        return NaturalLoopPresentation.canRetryVerification(stage: run.stage)
    }

    private var needsHumanCollaboration: Bool {
        guard let run else { return false }
        return run.stage == .failed || run.stage == .inconclusive
    }

    var body: some View {
        Group {
            if isLoading && run == nil {
                ProgressView("加载自然回详情…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, run == nil {
                NWEmptyState(title: "无法加载详情", systemImage: "wifi.exclamationmark", message: error)
            } else if let run {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.space24) {
                        VStack(alignment: .leading, spacing: AppTheme.space8) {
                            Text(run.offering?.loop.title ?? run.definition?.name ?? "自然回")
                                .font(.title.bold())
                            Text(run.offering?.loop.summary ?? run.definition?.description ?? "从意图到结果的协作单元")
                                .font(.body)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                NWStatusChip(
                                    text: NaturalLoopPresentation.boundaryTitle(run.boundaryKind),
                                    tint: NaturalLoopPresentation.boundaryTint(run.boundaryKind)
                                )
                                NWStatusChip(text: NaturalLoopPresentation.stageTitle(run.stage, style: .workspace))
                            }
                        }

                        if run.stage == .inconclusive {
                            Text("验证暂时无法判断结果是否成立，你可以重试验证或改由人协作处理。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else if run.stage == .failed {
                            Text("当前路径未达到可接受结果，需要重新判断下一步。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        detailSection("上下文") {
                            detailRow("发起方", run.context.initiatorReference)
                            detailRow("承接方", run.context.receiverReference)
                            detailRow("需求", run.context.demandID)
                            detailRow("订单", run.context.orderID)
                        }

                        detailSection("时间线") {
                            detailRow("开始", NaturalLoopPresentation.displayDate(run.startedAt))
                            detailRow("完成", NaturalLoopPresentation.displayDate(run.completedAt) ?? "进行中")
                            detailRow("创建", NaturalLoopPresentation.displayDate(run.createdAt))
                        }

                        if !run.evidence.isEmpty {
                            detailSection("事件流") {
                                ForEach(run.evidence) { event in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(event.type)
                                            .font(.subheadline.weight(.medium))
                                        if let actorReference = event.actorReference {
                                            Text(actorReference)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        if let createdAt = NaturalLoopPresentation.displayDate(event.createdAt) {
                                            Text(createdAt)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    if event.id != run.evidence.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }

                        if !run.interventions.isEmpty || !run.links.isEmpty {
                            detailSection("验证与关联") {
                                if !run.interventions.isEmpty {
                                    ForEach(run.interventions) { item in
                                        HStack {
                                            Text(item.verifierName ?? item.verifierCode ?? "验证步骤")
                                            Spacer()
                                            Text(item.status)
                                                .foregroundStyle(.secondary)
                                        }
                                        .font(.subheadline)
                                    }
                                }
                                if !run.links.isEmpty {
                                    ForEach(run.links) { item in
                                        HStack {
                                            Text(item.linkedDefinition?.name ?? "关联自然回")
                                            Spacer()
                                            Text(item.relation)
                                                .foregroundStyle(.secondary)
                                            NWStatusChip(text: NaturalLoopPresentation.stageTitle(item.linkedRunStage, style: .workspace))
                                        }
                                        .font(.subheadline)
                                    }
                                }
                            }
                        }

                        if let pollingPausedMessage {
                            Text(pollingPausedMessage)
                                .font(.caption)
                                .foregroundStyle(AppTheme.error)
                        }

                        if canRetry {
                            Button {
                                Task { await retry() }
                            } label: {
                                Label(isRetrying ? "重试中…" : "重试验证", systemImage: "arrow.clockwise")
                                    .frame(minWidth: 120)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRetrying)
                        }

                        if needsHumanCollaboration, let onHumanCollaboration {
                            Button(action: onHumanCollaboration) {
                                Label("转成人协作", systemImage: "person.2.fill")
                                    .frame(minWidth: 120)
                            }
                            .buttonStyle(.bordered)
                        }

                        if let retryMessage {
                            Text(retryMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(AppTheme.space24)
                    .frame(maxWidth: 720, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                NWDetailPlaceholder(
                    title: "选择一个自然回",
                    systemImage: "sparkles",
                    message: "左侧展示进行中的自然回；上方可输入意图生成路径。"
                )
            }
        }
        .background(AppTheme.workspaceBackground)
        .task(id: run?.id) {
            pollingPausedMessage = nil
            startPollingIfNeeded()
        }
        .onChange(of: run?.stage) { _, _ in
            startPollingIfNeeded()
        }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.space12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(AppTheme.space16)
        .ninewoodCard()
    }

    private func detailRow(_ title: String, _ value: String?) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "—")
        }
        .font(.subheadline)
    }

    private func retry() async {
        guard let run else { return }
        isRetrying = true
        defer { isRetrying = false }
        await onRetryVerification(run.id)
        retryMessage = "已提交重试验证"
        pollingPausedMessage = nil
        startPollingIfNeeded()
    }

    private func startPollingIfNeeded() {
        pollTask?.cancel()
        guard let run, !run.stage.isTerminal else {
            pollTask = nil
            return
        }
        let runID = run.id
        pollTask = Task {
            try? await Task.sleep(for: .seconds(12))
            while !Task.isCancelled {
                let ok = await onRefresh(runID)
                if !ok {
                    await MainActor.run {
                        pollingPausedMessage = "自动刷新已暂停（请求过于频繁或网络异常）。可稍后点左侧刷新。"
                    }
                    break
                }
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }
}
