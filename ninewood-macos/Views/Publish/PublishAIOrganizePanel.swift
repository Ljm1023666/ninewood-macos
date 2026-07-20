import SwiftUI

/// 发布页内的本地「AI 整理」面板（不在九木助手里填完整表单）。
struct PublishAIOrganizePanel: View {
    let mode: PublishAICardMode
    var frontendPreview: Bool = false
    var onApplied: (PublishAnalyzeResult) -> Void

    @Environment(AppSession.self) private var session
    @State private var draftText = ""
    @State private var turns: [Turn] = []
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var lastMissing: [String] = []
    @FocusState private var focused: Bool

    private struct Turn: Identifiable {
        let id = UUID()
        let role: Role
        let text: String
        enum Role { case user, assistant, system }
    }

    private var placeholder: String {
        mode == .service
            ? "例如：我能提供周末上门家电清洗，同城 2 小时响应，200 起…"
            : "例如：想找人周末上门修空调，预算 200 以内，浦东…"
    }

    private var emptyPrompt: String {
        mode == .service ? "你能提供什么样的服务？" : "你想找什么样的服务者？"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if turns.isEmpty {
                            emptyState
                        }
                        ForEach(turns) { turn in
                            bubble(turn)
                                .id(turn.id)
                        }
                        if !lastMissing.isEmpty {
                            missingBlock
                        }
                    }
                    .padding(14)
                }
                .onChange(of: turns.count) { _, _ in
                    if let last = turns.last?.id {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
            Divider()
            composer
        }
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant)
        }
        .onAppear { focused = true }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(AppTheme.primary)
            Text("AI 整理")
                .font(.subheadline.weight(.semibold))
            Text(mode == .service ? "服务卡" : "需求卡")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppTheme.softPrimary, in: Capsule())
            Spacer()
            if isBusy {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(emptyPrompt)
                .font(.headline)
            Text("用自然语言描述即可。AI 会整理标题、分类、预算/报价等字段到右侧表单；你仍可改，并在确认后提交。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }

    private func bubble(_ turn: Turn) -> some View {
        HStack {
            if turn.role == .user { Spacer(minLength: 24) }
            Text(turn.text)
                .font(.callout)
                .padding(10)
                .background(
                    turn.role == .user ? AppTheme.softPrimary : AppTheme.fill.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .frame(maxWidth: 280, alignment: turn.role == .user ? .trailing : .leading)
            if turn.role != .user { Spacer(minLength: 24) }
        }
    }

    private var missingBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("还缺这些信息（可继续补充）")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(lastMissing, id: \.self) { item in
                Text("· \(item)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.fill.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.error)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(placeholder, text: $draftText, axis: .vertical)
                    .lineLimit(2 ... 5)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(AppTheme.fill.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                    .focused($focused)
                    .onSubmit { Task { await submit() } }
                    .disabled(isBusy)

                Button {
                    Task { await submit() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(canSend ? AppTheme.primary : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help("开始整理")
            }
        }
        .padding(12)
    }

    private var canSend: Bool {
        !isBusy && !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() async {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        draftText = ""
        turns.append(Turn(role: .user, text: text))
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        if frontendPreview {
            let demo = PublishAnalyzeResult(
                title: mode == .service ? "预览服务：\(String(text.prefix(12)))" : "预览需求：\(String(text.prefix(12)))",
                summary: text,
                category: mode == .service ? "日常服务" : "家政",
                serviceType: "OFFLINE",
                budget: "200",
                schedule: nil,
                confidence: "medium",
                missingInfo: ["请补充期望完成时间"],
                suggestedKeywords: ["上门", "同城"],
                scopePath: nil,
                scopeLabels: nil,
                expectedOutcome: text,
                regionId: nil,
                readyToPublish: false,
                taxonomyLeafId: nil
            )
            apply(demo, assistantNote: "（预览）已根据描述整理到右侧字段，请继续核对。")
            return
        }

        do {
            let result = try await PublishAIService(client: session.apiClient)
                .analyzeDemand(text: text, mode: mode)
            let note: String
            if let summary = result.summary, !summary.isEmpty {
                note = summary
            } else if let title = result.title {
                note = "已整理出「\(title)」，请在右侧核对并完善。"
            } else {
                note = "已尝试解析，请补充更多细节后再次整理。"
            }
            apply(result, assistantNote: note)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            turns.append(Turn(role: .assistant, text: "整理失败：\(errorMessage ?? "未知错误")"))
        }
    }

    private func apply(_ result: PublishAnalyzeResult, assistantNote: String) {
        lastMissing = result.missingInfo ?? []
        turns.append(Turn(role: .assistant, text: assistantNote))
        onApplied(result)
    }
}
