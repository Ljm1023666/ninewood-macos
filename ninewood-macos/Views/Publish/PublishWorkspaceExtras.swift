import SwiftUI

/// 对齐 Windows `WorkspaceTools`：润色 + 待补充信息队列。
struct PublishWorkspaceToolsPanel: View {
    @Binding var fields: PublishWorkspaceFields
    @Binding var lockedFields: Set<String>
    @Binding var queue: PublishMissingQueueState
    var mode: PublishAICardMode
    var frontendPreview: Bool
    var apiClient: APIClient
    var onAskCurrent: (String) -> Void

    @State private var polishing: String?

    private var allItems: [String] {
        Array(Set(fields.missingInfo + queue.resolvedQueue)).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            polishSection
            if !allItems.isEmpty {
                missingSection
            }
        }
    }

    private var polishSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("润色工具")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                polishButton("缩短", key: "shorten")
                polishButton("扩写", key: "expand")
                polishButton("正式", key: "formal")
                polishButton("口语", key: "casual")
            }
        }
    }

    private func polishButton(_ title: String, key: String) -> some View {
        Button {
            Task { await polish(key) }
        } label: {
            if polishing == key {
                ProgressView().controlSize(.mini)
            } else {
                Text(title).font(.caption)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .disabled(fields.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || polishing != nil)
    }

    private var missingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("待补充信息")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if !queue.missingQueue.isEmpty {
                    Text("（\(queue.missingQueue.count) 项待回答）")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            ForEach(allItems, id: \.self) { item in
                missingRow(item)
            }

            if let prompt = queue.currentPrompt {
                Text(prompt)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.primary)
                    .padding(.top, 2)
            }
        }
    }

    private func missingRow(_ item: String) -> some View {
        let isQueued = queue.missingQueue.contains(item)
        let isAnswered = queue.answeredQueue.contains(item)
        let isResolved = queue.resolvedQueue.contains(item)
        return Button {
            guard !isAnswered, !isResolved else { return }
            queue.toggle(item)
            if queue.missingQueue.first == item {
                onAskCurrent(item)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isResolved ? "checkmark.circle.fill"
                      : isAnswered ? "pencil"
                      : isQueued ? "xmark.circle"
                      : "exclamationmark.triangle")
                    .foregroundStyle(isResolved ? .green : isQueued ? AppTheme.primary : .orange)
                    .font(.caption)
                Text(item)
                    .font(.caption)
                    .foregroundStyle(isResolved ? .secondary : AppTheme.onSurface)
                    .multilineTextAlignment(.leading)
                Spacer()
                if isQueued {
                    Text("待回答").font(.caption2).foregroundStyle(.secondary)
                } else if isAnswered {
                    Text("已收集").font(.caption2).foregroundStyle(.secondary)
                } else if isResolved {
                    Text("已解决").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(
                (isQueued ? AppTheme.softPrimary : AppTheme.fill.opacity(0.28)),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(isAnswered || isResolved)
    }

    @MainActor
    private func polish(_ action: String) async {
        let description = fields.description
        guard !description.isEmpty else { return }
        polishing = action
        defer { polishing = nil }
        let prompts: [String: String] = [
            "shorten": "将以下需求描述缩短 50%，保留核心信息，去除冗余修饰：\n\(description)",
            "expand": "将以下需求描述详细展开，补充合理的细节，让需求更完整：\n\(description)",
            "formal": "将以下需求描述改写成正式、专业的商务风格：\n\(description)",
            "casual": "将以下需求描述改写成口语化、亲切自然的风格：\n\(description)",
        ]
        guard let prompt = prompts[action] else { return }
        if frontendPreview {
            if !lockedFields.contains("description") {
                fields.description = action == "shorten" ? String(description.prefix(max(20, description.count / 2))) : description + "（已润色）"
            }
            return
        }
        do {
            let result = try await PublishAIService(client: apiClient)
                .analyzeDemandLongTimeout(text: prompt, mode: mode)
            if !lockedFields.contains("description"), let summary = result.summary, !summary.isEmpty {
                fields.description = summary
                lockedFields.insert("description")
            }
        } catch {
            // 静默失败，对齐 Windows
        }
    }
}

/// 对齐 Windows Canvas 卡牌预览（简化 2D）。
struct PublishCanvasCardPreview: View {
    let fields: PublishWorkspaceFields
    let isService: Bool
    @State private var flipped = true

    var body: some View {
        VStack(spacing: 16) {
            Text("Canvas 预览")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.18, green: 0.22, blue: 0.32),
                                Color(red: 0.08, green: 0.10, blue: 0.16),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(isService ? "SERVICE" : "DEMAND")
                                .font(.caption2.weight(.bold))
                                .tracking(1.2)
                                .foregroundStyle(.white.opacity(0.55))
                            Text(fields.title.isEmpty ? "标题待写入…" : fields.title)
                                .font(.title3.bold())
                                .foregroundStyle(.white)
                            Text(fields.description.isEmpty ? "描述内容将随输入同步写入…" : fields.description)
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.82))
                                .lineLimit(6)
                            Spacer(minLength: 0)
                            HStack {
                                Text(fields.budget.isEmpty ? "¥?" : "¥\(fields.budget)")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Spacer()
                                Text(fields.category.isEmpty ? "未分类" : fields.category)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        .padding(22)
                        .opacity(flipped ? 0 : 1)
                    }
                    .overlay {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("结构化摘要")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.55))
                            metaRow("类型", fields.serviceType == "OFFLINE" ? "线下" : fields.serviceType == "ONLINE" ? "线上" : "未选")
                            metaRow(isService ? "报价" : "预算", fields.budget.isEmpty ? "—" : fields.budget)
                            metaRow(isService ? "交付" : "时间", fields.schedule.isEmpty ? "—" : fields.schedule)
                            metaRow("分类", fields.category.isEmpty ? "—" : fields.category)
                            if !fields.scopeLabels.isEmpty {
                                Text(fields.scopeLabels.joined(separator: " · "))
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(22)
                        .opacity(flipped ? 1 : 0)
                    }
            }
            .frame(height: 320)
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.35)) { flipped.toggle() }
            }

            Text("点击卡片翻转 · Canvas 模式用左侧输入直接抽结构")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.55))
            Spacer()
            Text(value).font(.callout.weight(.medium)).foregroundStyle(.white)
        }
    }
}

/// 对齐 Windows `/demands/create/paths`：发布前确认匹配路径。
struct PublishConfirmPathsSheet: View {
    let fields: PublishWorkspaceFields
    let regionName: String?
    let isService: Bool
    let autoPaths: [String]
    @Binding var paths: [String]
    var isPublishing: Bool
    var onBack: () -> Void
    var onConfirm: () -> Void

    @State private var pathDraft = ""
    @State private var pathType = "tag"

    private let pathTypes = ["tag", "kw", "cat", "attr", "rgn"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("返回编辑", action: onBack)
                    .buttonStyle(.borderless)
                Spacer()
                Text(isService ? "确认服务卡" : "确认匹配路径")
                    .font(.headline)
                Spacer()
                Button {
                    onConfirm()
                } label: {
                    if isPublishing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(isService ? "保存草稿" : "确认发布")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPublishing)
                .controlSize(.small)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(isService ? "发布前置 · 核对服务卡字段" : "发布前置 · 路径决定需求如何被检索命中")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Group {
                        confirmRow("标题", fields.title)
                        confirmRow("描述", fields.description)
                        confirmRow("类型", fields.serviceType == "OFFLINE" ? "线下" : "线上")
                        confirmRow(isService ? "报价" : "预算", fields.budget)
                        confirmRow("分类", fields.category)
                        if let regionName {
                            confirmRow("地区", regionName)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("匹配路径")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("恢复自动") {
                                paths = autoPaths
                            }
                            .controlSize(.mini)
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], alignment: .leading, spacing: 6) {
                            ForEach(paths, id: \.self) { path in
                                HStack(spacing: 4) {
                                    Text(path).font(.caption2)
                                    Button {
                                        paths.removeAll { $0 == path }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppTheme.fill.opacity(0.4), in: Capsule())
                            }
                        }

                        HStack {
                            Picker("类型", selection: $pathType) {
                                ForEach(pathTypes, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 88)
                            TextField("值，如 家政", text: $pathDraft)
                                .textFieldStyle(.roundedBorder)
                            Button("添加") {
                                let raw = pathDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !raw.isEmpty else { return }
                                let value = raw.contains(":") ? raw : "\(pathType):\(raw)"
                                if !paths.contains(value), paths.count < 12 {
                                    paths.append(value)
                                }
                                pathDraft = ""
                            }
                            .disabled(pathDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Text("支持类型前缀 tag: / kw: / cat: · 最多 12 条")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 560, minHeight: 460)
    }

    private func confirmRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.callout)
                .textSelection(.enabled)
            Spacer()
        }
    }
}

/// 会话历史下拉（对齐 DemandSessionHistory）。
struct PublishSessionMenu: View {
    let sessions: [PublishWorkspaceSessionSnapshot]
    let activeId: String?
    var onSelect: (String) -> Void
    var onDelete: (String) -> Void

    var body: some View {
        Menu {
            if sessions.isEmpty {
                Text("暂无历史草稿")
            } else {
                ForEach(sessions) { s in
                    Button {
                        onSelect(s.id)
                    } label: {
                        HStack {
                            Text(s.title)
                            if s.id == activeId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                ForEach(sessions) { s in
                    Button("删除「\(s.title)」", role: .destructive) {
                        onDelete(s.id)
                    }
                }
            }
        } label: {
            Label("历史", systemImage: "clock.arrow.circlepath")
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("历史草稿")
        .accessibilityIdentifier("publish-ws-history")
    }
}
