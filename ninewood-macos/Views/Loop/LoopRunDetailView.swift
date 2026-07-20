import SwiftUI

/// 单次运行详情（对齐 Windows LoopRunDetailPage）。
struct LoopRunDetailView: View {
    @Environment(AppSession.self) private var session
    let runID: String
    var frontendPreview: Bool = false

    @State private var run: LoopRunDetailDTO?
    @State private var isLoading = false
    @State private var isRetrying = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                backRow
                if isLoading && run == nil {
                    ProgressView("读取运行详情…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if let errorMessage, run == nil {
                    Text(errorMessage)
                        .foregroundStyle(AppTheme.urgent)
                } else if let run {
                    detailBody(run)
                }
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("loop-run-detail")
        .task(id: runID) { await load() }
    }

    private var backRow: some View {
        HStack {
            Button {
                _ = session.navigation.navigate(to: "/loops/mine")
            } label: {
                Label("返回我的回", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            Spacer()
            Button {
                Task { await load() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func detailBody(_ run: LoopRunDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Text(LoopHubFormatting.kindLabel(run.loopKind))
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(LoopHubFormatting.kindTint(run.loopKind).opacity(0.14), in: Capsule())
                    .foregroundStyle(LoopHubFormatting.kindTint(run.loopKind))
                Text(LoopHubFormatting.statusLabel(run.status))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if canRetry(run) {
                    Button {
                        Task { await retry() }
                    } label: {
                        Label(isRetrying ? "重试中…" : "重试验证", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRetrying)
                }
            }

            Text(run.offering?.title ?? run.definition?.name ?? "运行详情")
                .font(.title.bold())

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(AppTheme.urgent)
            }

            jsonBlock("输入", run.inputJson)
            jsonBlock("期望结果", run.expectedOutcome)
            jsonBlock("实际结果", run.actualOutcome)

            if let verifications = run.verificationRuns, !verifications.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("验证链")
                        .font(.headline)
                    ForEach(verifications) { item in
                        HStack {
                            Text(item.verifier?.name ?? item.verifier?.code ?? item.id)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(item.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(AppTheme.fill.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            if let events = run.events, !events.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("事件时间线")
                        .font(.headline)
                    ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                        HStack(alignment: .top) {
                            Text(event.type)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text(event.createdAt ?? "—")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            linksSection(title: "子回", links: run.linksOut)
            linksSection(title: "父回", links: run.linksIn)
        }
    }

    private func jsonBlock(_ title: String, _ value: LoopJSONValue?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(LoopHubFormatting.prettyJSON(value))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.fill.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func linksSection(title: String, links: [LoopLinkDTO]?) -> some View {
        if let links, !links.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                ForEach(links) { link in
                    let target = link.targetRun ?? link.sourceRun
                    Button {
                        if let id = target?.id {
                            _ = session.navigation.navigate(to: "/loops/runs/\(id)")
                        }
                    } label: {
                        HStack {
                            Text(link.relation)
                                .font(.caption.weight(.semibold))
                            Text(target?.definition?.name ?? target?.id ?? "—")
                                .font(.subheadline)
                            Spacer()
                            Text(target?.status ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(target?.id == nil)
                }
            }
        }
    }

    private func canRetry(_ run: LoopRunDetailDTO) -> Bool {
        run.loopKind.uppercased() == "EARTH" && run.status.uppercased() == "INCONCLUSIVE"
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if frontendPreview {
            run = LoopRunPreviewFixtures.detail(id: runID)
            return
        }

        do {
            run = try await session.loopService.getRun(id: runID)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func retry() async {
        isRetrying = true
        errorMessage = nil
        defer { isRetrying = false }
        guard !frontendPreview else {
            await load()
            return
        }
        do {
            _ = try await session.loopService.retryVerification(runId: runID)
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

enum LoopRunPreviewFixtures {
    static func detail(id: String) -> LoopRunDetailDTO {
        LoopRunDetailDTO(
            id: id,
            loopKind: "EARTH",
            status: "SUCCEEDED",
            initiatorRef: "preview-user",
            receiverRef: nil,
            inputJson: .object(["title": .string("预览输入")]),
            expectedOutcome: .object(["ok": .bool(true)]),
            actualOutcome: .object(["ok": .bool(true), "note": .string("设计预览结果")]),
            demandId: nil,
            orderId: nil,
            parentRunId: nil,
            correlationId: nil,
            startedAt: nil,
            completedAt: nil,
            createdAt: nil,
            updatedAt: nil,
            definition: LoopDefinitionDTO(
                code: "preview.structure",
                name: "需求字段结构化",
                description: nil,
                loopKind: "EARTH",
                executionMode: nil,
                inputSchema: nil,
                outcomeSchema: nil
            ),
            offering: LoopOfferingBriefDTO(id: "preview-earth-1", title: "需求字段结构化", summary: nil),
            events: [
                LoopEventDTO(id: "e1", type: "TRIGGERED", actorRef: nil, visibility: nil, payload: nil, createdAt: nil),
                LoopEventDTO(id: "e2", type: "SUCCEEDED", actorRef: nil, visibility: nil, payload: nil, createdAt: nil),
            ],
            verificationRuns: [
                LoopVerificationRunDTO(
                    id: "v1",
                    status: "PASSED",
                    resultJson: .object(["ok": .bool(true)]),
                    createdAt: nil,
                    verifier: LoopVerifierDTO(id: "vr1", code: "preview.verify", name: "预览核验")
                ),
            ],
            linksOut: nil,
            linksIn: nil
        )
    }
}
