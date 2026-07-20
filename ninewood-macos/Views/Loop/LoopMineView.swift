import SwiftUI

/// 我的回：运行 inbox（对齐 Windows MyLoopsPage 单区版）。
struct LoopMineView: View {
    @Environment(AppSession.self) private var session
    var frontendPreview: Bool = false

    @State private var items: [MyLoopItemDTO] = []
    @State private var summary: MyLoopSummaryDTO?
    @State private var selectedKinds: Set<String> = ["HUMAN", "EARTH", "HEAVEN"]
    @State private var sort: String = "recent"
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pollTask: Task<Void, Never>?

    private let allKinds = ["HUMAN", "EARTH", "HEAVEN"]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .accessibilityIdentifier("loop-mine")
        .task {
            await reload()
            startPolling()
        }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
        .onChange(of: selectedKinds) { _, _ in
            Task { await reload() }
        }
        .onChange(of: sort) { _, _ in
            Task { await reload() }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            summaryChips
            Spacer()
            kindFilters
            Picker("排序", selection: $sort) {
                Text("最近").tag("recent")
                Text("完成度").tag("completion")
                Text("成功率").tag("success")
            }
            .labelsHidden()
            .frame(width: 110)
            Button {
                Task { await reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("刷新")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var summaryChips: some View {
        HStack(spacing: 8) {
            chip("全部", summary?.total)
            chip("进行中", summary?.active)
            chip("成功", summary?.succeeded)
            chip("失败", summary?.failed)
        }
    }

    private func chip(_ title: String, _ value: Int?) -> some View {
        Text("\(title) \(value ?? 0)")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppTheme.fill.opacity(0.4), in: Capsule())
            .foregroundStyle(.secondary)
    }

    private var kindFilters: some View {
        HStack(spacing: 6) {
            ForEach(allKinds, id: \.self) { kind in
                let on = selectedKinds.contains(kind)
                Button {
                    if on {
                        if selectedKinds.count > 1 { selectedKinds.remove(kind) }
                    } else {
                        selectedKinds.insert(kind)
                    }
                } label: {
                    Text(LoopHubFormatting.kindLabel(kind))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            on ? LoopHubFormatting.kindTint(kind).opacity(0.16) : AppTheme.fill.opacity(0.3),
                            in: Capsule()
                        )
                        .foregroundStyle(on ? LoopHubFormatting.kindTint(kind) : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && items.isEmpty {
            ProgressView("加载我的回…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, items.isEmpty {
            ContentUnavailableView("无法加载", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
        } else if items.isEmpty {
            ContentUnavailableView(
                "还没有运行记录",
                systemImage: "arrow.triangle.2.circlepath",
                description: Text("在「发现回」找到地回并运行后，会出现在这里。")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(items) { item in
                        Button {
                            _ = session.navigation.navigate(to: "/loops/runs/\(item.id)")
                        } label: {
                            LoopMineRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
        }
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if frontendPreview {
            items = LoopMinePreviewFixtures.items
            summary = LoopMinePreviewFixtures.summary
            return
        }

        do {
            let kinds = allKinds.filter { selectedKinds.contains($0) }
            let result = try await session.loopService.myRuns(
                kinds: kinds,
                sort: sort,
                limit: 40
            )
            items = result.items
            summary = result.summary
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        guard !frontendPreview else { return }
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { return }
                await reload()
            }
        }
    }
}

private struct LoopMineRow: View {
    let item: MyLoopItemDTO

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(LoopHubFormatting.kindLabel(item.kind))
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(LoopHubFormatting.kindTint(item.kind).opacity(0.14), in: Capsule())
                        .foregroundStyle(LoopHubFormatting.kindTint(item.kind))
                    Text(LoopHubFormatting.statusLabel(item.status))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(item.offering?.title ?? item.definition?.name ?? "未命名回")
                    .font(.headline)
                    .foregroundStyle(AppTheme.onSurface)
                if let summary = item.offering?.summary ?? item.definition?.description {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                if let progress = item.progress {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                }
                Text(shortTime(item.updatedDisplay))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).strokeBorder(AppTheme.outlineVariant)
        }
    }

    private func shortTime(_ raw: String?) -> String {
        guard let raw, let date = ISO8601DateFormatter().date(from: raw)
            ?? ISO8601DateFormatter.withFractional.date(from: raw)
        else { return "—" }
        return date.formatted(.dateTime.month().day().hour().minute())
    }
}

private extension MyLoopItemDTO {
    var updatedDisplay: String? { completedAt ?? startedAt ?? createdAt }
}

private extension ISO8601DateFormatter {
    static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

enum LoopMinePreviewFixtures {
    static let summary = MyLoopSummaryDTO(
        total: 2,
        active: 1,
        succeeded: 1,
        failed: 0,
        successRate: 0.5,
        byKind: nil
    )

    static let items: [MyLoopItemDTO] = [
        MyLoopItemDTO(
            id: "preview-run-1",
            kind: "EARTH",
            status: "SUCCEEDED",
            progress: 1,
            demandId: nil,
            orderId: nil,
            initiatorRef: nil,
            receiverRef: nil,
            startedAt: nil,
            completedAt: nil,
            createdAt: nil,
            eventCount: 3,
            latestEvent: nil,
            definition: LoopDefinitionDTO(
                code: "preview.structure",
                name: "需求字段结构化",
                description: "预览成功运行",
                loopKind: "EARTH",
                executionMode: nil,
                inputSchema: nil,
                outcomeSchema: nil
            ),
            offering: LoopOfferingBriefDTO(id: "preview-earth-1", title: "需求字段结构化", summary: "整理口语需求")
        ),
        MyLoopItemDTO(
            id: "preview-run-2",
            kind: "HEAVEN",
            status: "VERIFYING",
            progress: 0.6,
            demandId: nil,
            orderId: nil,
            initiatorRef: nil,
            receiverRef: nil,
            startedAt: nil,
            completedAt: nil,
            createdAt: nil,
            eventCount: 1,
            latestEvent: nil,
            definition: LoopDefinitionDTO(
                code: "preview.verify",
                name: "结果核验",
                description: "预览核验中",
                loopKind: "HEAVEN",
                executionMode: nil,
                inputSchema: nil,
                outcomeSchema: nil
            ),
            offering: nil
        ),
    ]
}
