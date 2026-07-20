import SwiftUI

/// 发现回：意图 → recommend → 地回卡 / 人回草稿（对齐 Windows LoopDiscoverPage）。
struct LoopDiscoverView: View {
    @Environment(AppSession.self) private var session
    var frontendPreview: Bool = false

    @State private var query = ""
    @State private var result: LoopRecommendationResultDTO?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(AppTheme.urgent)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.urgent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                if let result {
                    resultsSection(result)
                }
            }
            .padding(28)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("loop-discover")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("NATURAL LOOP")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(0.8)

            Text("说出你想完成的事")
                .font(.largeTitle.bold())
                .foregroundStyle(AppTheme.onSurface)

            Text("我们先理解需求，再寻找能执行、能验证、能形成结果的地回。")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                Text("你的需求")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(
                    "例如：把这段口语化需求整理成结构化字段，并检查路径是否有效",
                    text: $query,
                    axis: .vertical
                )
                .lineLimit(3 ... 6)
                .textFieldStyle(.plain)
                .padding(12)
                .background(AppTheme.fill.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("loop-discover-query")

                Button {
                    Task { await submit() }
                } label: {
                    Label(isLoading ? "正在寻找…" : "寻找合适的回", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isLoading || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("loop-discover-submit")
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func resultsSection(_ result: LoopRecommendationResultDTO) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            resolvedPaths(result)

            if !result.items.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                    ForEach(result.items) { item in
                        LoopEarthCard(item: item) {
                            _ = session.navigation.navigate(to: "/loops/offerings/\(item.id)")
                        }
                    }
                }
            }

            if let fallback = result.humanFallback {
                humanFallbackCard(fallback)
            }
        }
    }

    private func resolvedPaths(_ result: LoopRecommendationResultDTO) -> some View {
        let paths = (result.resolved?.paths ?? []) + (result.resolved?.facets ?? [])
        return VStack(alignment: .leading, spacing: 8) {
            Text("已理解的路径")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if paths.isEmpty {
                Text("尚未解析到明确路径")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                FlowWrap(spacing: 6) {
                    ForEach(paths, id: \.self) { path in
                        Text(path)
                            .font(.caption.monospaced())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.fill.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).strokeBorder(AppTheme.outlineVariant)
        }
    }

    private func humanFallbackCard(_ fallback: HumanFallbackDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("没有可直接执行的地回", systemImage: "person.2")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.human)
            Text("把它转为一个待确认的人回")
                .font(.title3.bold())
            Text("我们已经整理好草稿。下一步仍由你检查和确认，不会自动发布。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                continueAsHuman(fallback)
            } label: {
                Label("检查人回草稿", systemImage: "arrow.right")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("loop-discover-human-fallback")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.human.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(AppTheme.human.opacity(0.25))
        }
    }

    private func submit() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if frontendPreview {
            result = LoopDiscoverPreviewFixtures.sample(query: q)
            return
        }

        do {
            result = try await session.loopService.recommendEarth(query: q)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func continueAsHuman(_ fallback: HumanFallbackDTO) {
        let title = (fallback.title ?? "发布人回").replacingOccurrences(of: "发布人回：", with: "")
        let description = fallback.description ?? query
        // 正式会话：写入本地草稿会话，再导航到需求工作区（不静默发布）
        if !frontendPreview {
            var snap = PublishWorkspaceSessionStore.makeEmpty(kind: .demand)
            snap.title = title.isEmpty ? "新人回草稿" : title
            snap.input = description
            if !description.isEmpty {
                snap.messages = [
                    .init(id: UUID().uuidString, role: "user", content: description),
                ]
            }
            var fields = PublishWorkspaceFields()
            fields.title = title
            fields.description = description
            fields.scopeLabels = fallback.paths ?? []
            fields.suggestedKeywords = fallback.facets ?? []
            fields.confidence = "medium"
            snap.fields = PublishWorkspaceFieldsDTO(fields)
            snap.confidence = "medium"
            snap.readyToPublish = false
            PublishWorkspaceSessionStore.upsert(snap, kind: .demand)
        }
        session.setPublishHandoff(
            PublishDraftHandoff(
                kind: .demand,
                title: title,
                description: description,
                expectedOutcome: description,
                source: "loop-human-fallback"
            )
        )
        _ = session.navigation.navigate(to: "/demands/create")
    }
}

private struct LoopEarthCard: View {
    let item: LoopRecommendationDTO
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("地回")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(LoopHubFormatting.kindTint("EARTH").opacity(0.14), in: Capsule())
                    .foregroundStyle(LoopHubFormatting.kindTint("EARTH"))
                Spacer()
                Label(
                    "\(item.verification?.verifierCount ?? 0) 个必要验证",
                    systemImage: "checkmark.shield"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Text(item.title)
                .font(.headline)
                .foregroundStyle(AppTheme.onSurface)
            Text(item.summary ?? item.definitionDescription ?? "平台内置的可执行回。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            VStack(alignment: .leading, spacing: 6) {
                Label("预计 \(LoopHubFormatting.duration(item.metrics?.avgDurationMs))", systemImage: "clock")
                Label("自动执行，结果由天回验证", systemImage: "cpu")
                Label(
                    "公开成功率 \(LoopHubFormatting.publicRate(item.metrics?.publicSuccessRate))",
                    systemImage: "checkmark.shield"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let reasons = item.match?.reasons, !reasons.isEmpty {
                FlowWrap(spacing: 6) {
                    ForEach(reasons, id: \.self) { reason in
                        Text(reason)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppTheme.softPrimary, in: Capsule())
                            .foregroundStyle(AppTheme.primary)
                    }
                }
            }

            Button("查看输入与结果契约", action: onOpen)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(AppTheme.outlineVariant)
        }
    }
}

/// 简易流式换行（避免依赖外部 FlowLayout）。
private struct FlowWrap<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        // macOS 14+：用 LazyVGrid 近似；子项自适应宽度不够精确但足够展示 chips
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 72), spacing: spacing, alignment: .leading)],
            alignment: .leading,
            spacing: spacing
        ) {
            content()
        }
    }
}

enum LoopDiscoverPreviewFixtures {
    static func sample(query: String) -> LoopRecommendationResultDTO {
        LoopRecommendationResultDTO(
            query: query,
            resolved: LoopResolvedQueryDTO(
                paths: ["tag:预览", "cat:日常服务"],
                facets: ["bkt:price=200_500"],
                suggestions: nil,
                status: "partial"
            ),
            items: [
                LoopRecommendationDTO(
                    id: "preview-earth-1",
                    title: "需求字段结构化",
                    summary: "把口语需求整理成标题、预算与路径。",
                    loopKind: "EARTH",
                    definitionCode: "preview.demand.structure",
                    definitionName: "结构整理",
                    definitionDescription: "设计预览地回",
                    paths: ["tag:预览"],
                    requiresVerification: true,
                    executionMode: "SYNC",
                    metrics: LoopOfferingMetricsDTO(
                        dealRate: 0.9,
                        avgDurationMs: 12_000,
                        publicSuccessRate: nil,
                        sampleSize: 3,
                        successRateStatus: "ADAPTING"
                    ),
                    verification: LoopVerificationSummaryDTO(status: "VERIFIED", verifierCount: 1),
                    match: LoopMatchDTO(
                        matchedPaths: ["tag:预览"],
                        textMatched: true,
                        reasons: ["命中预览标签"]
                    )
                ),
            ],
            humanFallback: nil
        )
    }
}
