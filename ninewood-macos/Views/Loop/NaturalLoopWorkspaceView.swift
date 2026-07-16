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
    @State private var detailError: String?

    var body: some View {
        VStack(spacing: 0) {
            intentBar
            Divider()
            SplitListDetailShell(minListWidth: 300, idealListWidth: 340) {
                inboxList
            } detail: {
                detailPane
            }
        }
        .navigationTitle("自然回")
        .task { await loadInbox() }
        .sheet(isPresented: $showHumanDraft) {
            CreateDemandView(
                initialTitle: humanDraftTitle,
                initialOutcome: humanDraftOutcome
            )
            .environment(session)
            .frame(minWidth: 560, minHeight: 640)
        }
        .sheet(isPresented: $showAgentSheet) {
            NavigationStack {
                AgentChatView(initialPrompt: query.trimmingCharacters(in: .whitespacesAndNewlines))
                    .environment(session)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { showAgentSheet = false }
                        }
                    }
            }
            .frame(minWidth: 900, minHeight: 640)
        }
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
