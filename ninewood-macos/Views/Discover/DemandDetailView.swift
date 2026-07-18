import SwiftUI
import AppKit

struct DemandDetailView: View {
    enum PoolMode {
        case standard
        case activePool
        case deadPool
    }

    let poolMode: PoolMode
    let previewMode: Bool
    @Environment(AppSession.self) private var session
    @State private var model: DemandDetailFeatureModel
    @State private var showApplySheet = false
    @State private var showBidSheet = false
    @State private var showReportSheet = false
    @State private var shareAlertMessage: String?

    init(
        demand: Demand,
        poolMode: PoolMode = .standard,
        previewMode: Bool = false
    ) {
        self.poolMode = poolMode
        self.previewMode = previewMode
        _model = State(initialValue: DemandDetailFeatureModel(demand: demand))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let refreshError = model.refreshError {
                        Text(refreshError)
                            .font(.caption)
                            .foregroundStyle(AppTheme.error)
                            .padding(.bottom, AppTheme.space12)
                    }
                    metaBlock
                    Divider()
                    if poolMode == .standard {
                        countdownCard
                        Divider()
                        outcomeCard
                        Divider()
                        descriptionCard
                        Divider()
                        tagsCard
                        Divider()
                        deadlineCard
                        Divider()
                        applicantCard
                        Divider()
                        trustCard
                        if !model.demand.mediaUrls.isEmpty || previewMode {
                            Divider()
                            attachmentsCard
                        }
                    } else {
                        outcomeCard
                        Divider()
                        priceCard
                        if !model.demand.mediaUrls.isEmpty { Divider() }
                        attachmentsCard
                        Divider()
                        infoCard
                        Divider()
                        publisherCard
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, AppTheme.space24)
                .padding(.bottom, AppTheme.space24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            applyBar
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.surface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.surface)
        .toolbar {
            if !previewMode {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        if model.isRefreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("刷新", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(model.isRefreshing)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.toggleFavorite() }
                } label: {
                    if model.isFavoriting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(model.isFavorited ? "已收藏" : "收藏", systemImage: model.isFavorited ? "bookmark.fill" : "bookmark")
                    }
                }
                .disabled(model.isFavoriting)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("分享…") { copyShareLink() }
                    Button("举报…") {
                        guard !previewMode else { return }
                        showReportSheet = true
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis")
                }
            }
        }
        .task(id: model.demand.id) {
            guard !previewMode else { return }
            model.configure(
                demandRepository: session.demandRepository,
                userRepository: session.userRepository
            )
            await model.load()
        }
        .sheet(isPresented: $showApplySheet) {
            ApplyDemandSheet { reason in
                Task { await model.apply(reason: reason) }
            }
            .frame(minWidth: 420, minHeight: 280)
        }
        .sheet(isPresented: $showBidSheet) {
            BidDemandSheet { price, message in
                Task { await model.bid(price: price, message: message) }
            }
            .frame(minWidth: 420, minHeight: 300)
        }
        .sheet(isPresented: $showReportSheet) {
            DemandReportSheet(
                demandTitle: model.demand.title,
                onSubmit: { category, reason in
                    Task { await submitReport(category: category, reason: reason) }
                }
            )
            .frame(minWidth: 420, minHeight: 320)
        }
        .alert("需求", isPresented: Binding(
            get: { model.actionMessage != nil || model.actionError != nil || shareAlertMessage != nil },
            set: {
                if !$0 {
                    model.clearFeedback()
                    shareAlertMessage = nil
                }
            }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(shareAlertMessage ?? model.actionMessage ?? model.actionError ?? "")
        }
    }

    private func copyShareLink() {
        let url = "https://tothetomorrow.com/demands/\(model.demand.id)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        shareAlertMessage = "链接已复制到剪贴板：\(url)"
    }

    private func submitReport(category: String, reason: String) async {
        let targetUserId = model.demand.publisher.id
        guard targetUserId != "unknown", !targetUserId.isEmpty else {
            model.actionError = "无法确定被举报用户"
            return
        }
        do {
            try await session.reportService.report(
                demandId: model.demand.id,
                category: category,
                reason: reason,
                targetUserId: targetUserId
            )
            showReportSheet = false
            model.actionMessage = "举报已提交"
        } catch {
            model.actionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Blocks

    /// 详情只呈现需求信息本身；装饰性封面只出现在左侧列表作预览（类似短视频封面 vs 正片）。
    private var metaBlock: some View {
        let displayDemand = model.demand
        return VStack(alignment: .leading, spacing: AppTheme.space16) {
            Text(displayDemand.title)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: AppTheme.space12) {
                publisherAvatar(size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(displayDemand.publisher.name)
                            .font(.body.weight(.semibold))
                        Text("已认证")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppTheme.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.softPrimary, in: Capsule())
                            .accessibilityLabel("已认证")
                    }
                    HStack(spacing: 6) {
                        Circle()
                            .fill(AppTheme.openStatus)
                            .frame(width: 7, height: 7)
                        Text(previewMode || poolMode == .standard
                             ? "在线 · 通常 10 分钟内回复"
                             : "信用分 \(displayDemand.publisher.creditScore)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(displayDemand.minPrice.currencyText)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                    Text("报酬")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, AppTheme.space16)
    }

    @ViewBuilder
    private func publisherAvatar(size: CGFloat) -> some View {
        if previewMode {
            Image("AvatarLinXia")
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(AppTheme.outlineVariant, lineWidth: 1) }
        } else {
            NWAvatarView(
                url: model.demand.publisher.avatarMediaURL,
                name: model.demand.publisher.name,
                size: size
            )
        }
    }

    private var outcomeCard: some View {
        let displayDemand = model.demand
        return HStack(alignment: .top, spacing: AppTheme.space16) {
            sectionLabel(poolMode == .standard ? "期望成果" : "期望效果", systemImage: "target")
            Text(displayDemand.expectedOutcome)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, AppTheme.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var countdownCard: some View {
        HStack(spacing: AppTheme.space16) {
            sectionLabel("可见倒计时", systemImage: "clock")
            Text(model.demand.countdownText)
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(AppTheme.error)
            Spacer(minLength: 0)
        }
        .padding(.vertical, AppTheme.space12)
    }

    private var descriptionCard: some View {
        HStack(alignment: .top, spacing: AppTheme.space16) {
            sectionLabel("需求描述", systemImage: "doc.text")
            VStack(alignment: .leading, spacing: 8) {
                if previewMode {
                    Text("我们在做一款面向大学生的学习规划 App，当前收集了大量用户反馈和需求，希望你帮忙梳理并提炼核心需求，归类整理，形成可落地的需求清单与洞察建议。")
                    Text("1. 整理并去重用户反馈，归纳核心诉求；\n2. 按功能模块分类，补充场景与优先级；\n3. 输出结构化文档（建议用表格或思维导图）。")
                } else {
                    Text(model.demand.expectedOutcome)
                }
            }
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, AppTheme.space12)
    }

    private var tagsCard: some View {
        let displayDemand = model.demand
        return HStack(alignment: .top, spacing: AppTheme.space16) {
            sectionLabel("相关标签", systemImage: "tag")
            if displayDemand.tags.isEmpty {
                Text("—")
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: AppTheme.space8) {
                    ForEach(Array(displayDemand.tags.enumerated()), id: \.element) { index, tag in
                        NWStatusChip(text: tag, tint: tagTint(for: tag, index: index))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, AppTheme.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var deadlineCard: some View {
        HStack(spacing: AppTheme.space16) {
            sectionLabel("交付期限", systemImage: "calendar")
            Text(model.demand.deadlineText)
            Spacer(minLength: 0)
        }
        .padding(.vertical, AppTheme.space12)
    }

    private var applicantCard: some View {
        let filled = Double(model.demand.applicantCount)
        let limit = max(Double(model.demand.applicantLimit), 1)
        return HStack(spacing: AppTheme.space16) {
            sectionLabel("已有接单", systemImage: "person.2")
            Text("\(model.demand.applicantCount) / \(model.demand.applicantLimit) 人")
                .font(.body.weight(.medium))
                .foregroundStyle(AppTheme.primary)
            ProgressView(value: min(filled / limit, 1))
                .tint(AppTheme.primary)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .padding(.vertical, AppTheme.space12)
    }

    private var trustCard: some View {
        HStack(alignment: .top, spacing: AppTheme.space16) {
            sectionLabel("信任凭证", systemImage: "checkmark.shield")
            HStack(spacing: 8) {
                trustPill("实名认证")
                trustPill("历史完成 \(model.demand.publisher.completedOrders)")
                trustPill("好评率 \(Int(model.demand.publisher.goodRate * 100))%")
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, AppTheme.space12)
    }

    private func trustPill(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.openStatus)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.openStatus.opacity(0.08), in: Capsule())
            .overlay {
                Capsule().strokeBorder(AppTheme.openStatus.opacity(0.45), lineWidth: 1)
            }
    }

    private var priceCard: some View {
        let displayDemand = model.demand
        return HStack(alignment: .top, spacing: AppTheme.space16) {
            sectionLabel("报价与时限", systemImage: "calendar")
            VStack(spacing: 0) {
                row("期望报价", displayDemand.expectedPrice?.currencyText ?? "—")
                Divider()
                row("最低报价限额", displayDemand.minPrice.currencyText)
                Divider()
                row(
                    "托管金额",
                    displayDemand.deposit?.currencyText ?? "发布时按最低报价托管"
                )
                Divider()
                row("完成时限", displayDemand.deadlineText, valueColor: AppTheme.error)
                if let stage = displayDemand.lifecycleStage, !stage.isEmpty {
                    Divider()
                    row("生命周期", stage)
                }
            }
        }
        .padding(.vertical, AppTheme.space8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attachmentsCard: some View {
        let urls = model.demand.mediaUrls
        return Group {
            if !urls.isEmpty || previewMode {
                HStack(alignment: .top, spacing: AppTheme.space16) {
                    sectionLabel("附件", systemImage: "paperclip")
                    VStack(alignment: .leading, spacing: AppTheme.space8) {
                        ForEach(urls, id: \.self) { path in
                            if let url = APIConfig.mediaURL(path) {
                                Link(destination: url) {
                                    Label(url.lastPathComponent, systemImage: "doc")
                                        .font(.subheadline)
                                }
                            } else {
                                Text(path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if urls.isEmpty, previewMode {
                            attachmentPlaceholder
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, AppTheme.space16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var attachmentPlaceholder: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.title3)
                .foregroundStyle(AppTheme.error)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("用户反馈与需求原始数据.pdf")
                    .font(.subheadline.weight(.medium))
                Text("1.8 MB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(AppTheme.surfaceLow, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
        }
    }

    private var infoCard: some View {
        let displayDemand = model.demand
        return HStack(alignment: .top, spacing: AppTheme.space16) {
            sectionLabel("服务信息", systemImage: "tag")
            VStack(alignment: .leading, spacing: AppTheme.space12) {
                if !displayDemand.tags.isEmpty {
                    FlowLayout(spacing: AppTheme.space8) {
                        ForEach(displayDemand.tags, id: \.self) { tag in
                            NWStatusChip(text: tag, tint: AppTheme.primary)
                        }
                    }
                }
                Label(displayDemand.distanceText + " · 位置已模糊", systemImage: "location")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, AppTheme.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var publisherCard: some View {
        let displayDemand = model.demand
        return HStack(alignment: .top, spacing: AppTheme.space16) {
            sectionLabel("发布者", systemImage: "person")
            NWAvatarView(
                url: displayDemand.publisher.avatarMediaURL,
                name: displayDemand.publisher.name,
                size: 48
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(displayDemand.publisher.name)
                    .font(.headline)
                Label("信用分 \(displayDemand.publisher.creditScore)", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, AppTheme.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var applyBar: some View {
        let displayDemand = model.demand
        return VStack(spacing: 10) {
            if poolMode == .deadPool {
                Button {
                    Task { await model.snatch() }
                } label: {
                    Text(model.isSnatching ? "抢单中…" : "抢单")
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isSnatching)
            } else if poolMode == .standard {
                // `03-discover`：请求接单 + 收藏（卡池应标留在卡池页）
                HStack(spacing: 12) {
                    Button {
                        showApplySheet = true
                    } label: {
                        Text("请求接单")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(
                                displayDemand.status.acceptsRequests
                                    ? AppTheme.primary
                                    : AppTheme.fill,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!displayDemand.status.acceptsRequests)

                    Button {
                        Task { await model.toggleFavorite() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: model.isFavorited ? "star.fill" : "star")
                            Text(model.isFavorited ? "已收藏" : "收藏")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.primary)
                        .frame(width: 128)
                        .frame(height: 42)
                        .background(
                            Color.white,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(AppTheme.primary.opacity(0.55), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isFavoriting)
                }

                Text("请求后需等待对方同意")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .frame(maxWidth: .infinity)
            } else if poolMode == .activePool {
                Button {
                    showBidSheet = true
                } label: {
                    Text("参与应标")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            displayDemand.status.acceptsRequests
                                ? AppTheme.primary
                                : AppTheme.fill,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!displayDemand.status.acceptsRequests)

                Text("提交报价与说明；应标为意向报价，需求方接受申请人后才会生成订单。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: AppTheme.space16) {
                    Spacer(minLength: 0)
                    Button {
                        showApplySheet = true
                    } label: {
                        Text("请求接单")
                            .frame(width: 200)
                            .frame(height: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!displayDemand.status.acceptsRequests)

                    Button {
                        showBidSheet = true
                    } label: {
                        Text("卡池应标")
                            .frame(width: 200)
                            .frame(height: 36)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!displayDemand.status.acceptsRequests)
                    Spacer(minLength: 0)
                }

                Text("正式成单：请求接单 → 需求方接受。卡池应标只是意向报价，不会生成订单。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func tagTint(for tag: String, index: Int) -> Color {
        if tag.contains("研究") || tag.contains("分析") {
            return AppTheme.openStatus
        }
        return index == 0 ? AppTheme.primary : AppTheme.openStatus
    }

    private func row(_ title: String, _ value: String, valueColor: Color = AppTheme.onSurface) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium).foregroundStyle(valueColor)
        }
        .font(.body)
        .padding(.vertical, 12)
    }

    private func sectionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.body.weight(.medium))
            .frame(width: 118, alignment: .leading)
    }

}

/// 简单流式标签排布（避免硬换行挤压）
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

private struct ApplyDemandSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    var onSubmit: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.space16) {
            Text("请求接单")
                .font(.title2.bold())
            Text("请求接单不等于正式接单。双方各发一条消息后，5 分钟沟通计时才会开始。")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $reason)
                .font(.body)
                .frame(minHeight: 120)
                .padding(AppTheme.space8)
                .background(AppTheme.fill.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("提交请求") {
                    onSubmit(reason.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(AppTheme.space24)
    }
}

private struct BidDemandSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var offerPrice = ""
    @State private var message = ""
    var onSubmit: (Decimal?, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.space16) {
            Text("卡池应标")
                .font(.title2.bold())
            Text("提交报价与说明。若该需求当前不可应标，服务器会返回原因。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text("报价（可选）")
                Spacer()
                TextField("金额", text: $offerPrice)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            TextEditor(text: $message)
                .font(.body)
                .frame(minHeight: 100)
                .padding(AppTheme.space8)
                .background(AppTheme.fill.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("提交应标") {
                    let price = offerPrice.isEmpty ? nil : Decimal(string: offerPrice)
                    onSubmit(price, message.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(AppTheme.space24)
    }
}

private struct DemandReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let demandTitle: String
    var onSubmit: (String, String) -> Void

    private let categories: [(id: String, label: String)] = [
        ("spam", "垃圾信息"),
        ("abuse", "辱骂骚扰"),
        ("adult", "不当内容"),
        ("scam", "诈骗可疑"),
        ("other", "其他"),
    ]

    @State private var category = "spam"
    @State private var reason = ""

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.space16) {
            Text("举报需求")
                .font(.title2.bold())
            Text(demandTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Picker("类别", selection: $category) {
                ForEach(categories, id: \.id) { item in
                    Text(item.label).tag(item.id)
                }
            }
            TextEditor(text: $reason)
                .font(.body)
                .frame(minHeight: 120)
                .padding(AppTheme.space8)
                .background(AppTheme.fill.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("提交举报") {
                    onSubmit(category, reason.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .buttonStyle(.borderedProminent)
                .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(AppTheme.space24)
    }
}
