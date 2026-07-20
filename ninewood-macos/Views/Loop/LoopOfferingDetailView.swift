import SwiftUI

/// Offering 详情 + 运行（对齐 Windows LoopOfferingDetailPage 精简版：先保证 free 可跑）。
struct LoopOfferingDetailView: View {
    @Environment(AppSession.self) private var session
    let offeringID: String
    var frontendPreview: Bool = false

    @State private var offering: LoopOfferingItemDTO?
    @State private var isLoading = false
    @State private var isRunning = false
    @State private var errorMessage: String?
    @State private var runError: String?
    @State private var freeTitle = ""
    @State private var freeDescription = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                backRow
                if isLoading && offering == nil {
                    ProgressView("加载能力…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if let errorMessage, offering == nil {
                    Text(errorMessage)
                        .foregroundStyle(AppTheme.urgent)
                } else if let offering {
                    detailBody(offering)
                }
            }
            .padding(28)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("loop-offering-detail")
        .task(id: offeringID) { await load() }
    }

    private var backRow: some View {
        Button {
            _ = session.navigation.navigate(to: "/loops/discover")
        } label: {
            Label("返回发现回", systemImage: "chevron.left")
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private func detailBody(_ offering: LoopOfferingItemDTO) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Text(LoopHubFormatting.kindLabel(offering.loopKind))
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(LoopHubFormatting.kindTint(offering.loopKind).opacity(0.14), in: Capsule())
                    .foregroundStyle(LoopHubFormatting.kindTint(offering.loopKind))
                Text(consumerKindLabel(offering.loopKind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(offering.title)
                .font(.largeTitle.bold())
            Text(offering.summary ?? offering.definitionDescription ?? "可执行的地回能力。")
                .font(.body)
                .foregroundStyle(.secondary)

            metricsRow(offering)

            pipelineCard(offering)

            runPanel(offering)

            if let runError {
                Text(runError)
                    .font(.callout)
                    .foregroundStyle(AppTheme.urgent)
            }
        }
    }

    private func consumerKindLabel(_ kind: String) -> String {
        switch kind.uppercased() {
        case "EARTH": return "立即使用"
        case "HEAVEN": return "系统自动"
        case "HUMAN": return "找人帮忙"
        default: return kind
        }
    }

    private func metricsRow(_ offering: LoopOfferingItemDTO) -> some View {
        HStack(spacing: 16) {
            metric("预计耗时", LoopHubFormatting.duration(offering.metrics?.avgDurationMs))
            metric("公开成功率", LoopHubFormatting.publicRate(offering.metrics?.publicSuccessRate))
            metric(
                "必要验证",
                "\(offering.verification?.verifierCount ?? (offering.requiresVerification == true ? 1 : 0)) 个"
            )
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.fill.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private func pipelineCard(_ offering: LoopOfferingItemDTO) -> some View {
        let nodes = ["触发", offering.title, "执行", "天回验证", "闭环"]
        return VStack(alignment: .leading, spacing: 10) {
            Text("执行管线")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                ForEach(Array(nodes.enumerated()), id: \.offset) { index, node in
                    Text(node)
                        .font(.caption.weight(index == 1 ? .bold : .regular))
                        .foregroundStyle(index == 1 ? AppTheme.primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            index == 1 ? AppTheme.softPrimary : Color.clear,
                            in: Capsule()
                        )
                    if index < nodes.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
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

    private func runPanel(_ offering: LoopOfferingItemDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("运行此能力")
                .font(.headline)
            Text("自由输入（不绑定需求卡）")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("标题（可选）", text: $freeTitle)
                .textFieldStyle(.roundedBorder)
            TextField("描述 / 输入内容", text: $freeDescription, axis: .vertical)
                .lineLimit(3 ... 6)
                .textFieldStyle(.roundedBorder)

            Button {
                Task { await run(offering) }
            } label: {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                } else {
                    Label("开始运行", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isRunning)
            .accessibilityIdentifier("loop-offering-run")
        }
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(AppTheme.outlineVariant)
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if frontendPreview {
            offering = LoopOfferingPreviewFixtures.item(id: offeringID)
            freeTitle = "预览标题"
            freeDescription = "预览输入内容"
            return
        }

        do {
            offering = try await session.loopService.getOffering(id: offeringID)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func run(_ offering: LoopOfferingItemDTO) async {
        isRunning = true
        runError = nil
        defer { isRunning = false }

        if frontendPreview {
            _ = session.navigation.navigate(to: "/loops/runs/preview-run-1")
            return
        }

        var input: [String: String] = [:]
        let title = freeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = freeDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { input["title"] = title }
        if !description.isEmpty { input["description"] = description }

        do {
            let result = try await session.loopService.runOffering(id: offering.id, input: input)
            if let runId = result.runId, !runId.isEmpty {
                _ = session.navigation.navigate(to: "/loops/runs/\(runId)")
            } else {
                runError = "已提交，但未返回运行 ID。"
            }
        } catch {
            runError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

enum LoopOfferingPreviewFixtures {
    static func item(id: String) -> LoopOfferingItemDTO {
        LoopOfferingItemDTO(
            id: id,
            title: "需求字段结构化",
            summary: "把口语需求整理成标准字段。",
            loopKind: "EARTH",
            definitionCode: "preview.demand.structure",
            definitionName: "结构整理",
            definitionDescription: "设计预览能力",
            paths: ["tag:预览"],
            requiresVerification: true,
            metrics: LoopOfferingMetricsDTO(
                dealRate: 0.88,
                avgDurationMs: 15_000,
                publicSuccessRate: nil,
                sampleSize: 4,
                successRateStatus: "ADAPTING"
            ),
            verification: LoopVerificationSummaryDTO(status: "VERIFIED", verifierCount: 1),
            inputSchema: nil,
            outcomeSchema: nil
        )
    }
}
