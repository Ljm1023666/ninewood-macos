import SwiftUI

struct DemandDetailView: View {
    enum PoolMode {
        case standard
        case activePool
        case deadPool
    }

    let poolMode: PoolMode
    @Environment(AppSession.self) private var session
    @State private var displayDemand: Demand
    @State private var showApplySheet = false
    @State private var showBidSheet = false
    @State private var applyMessage: String?
    @State private var applyError: String?
    @State private var isFavoriting = false
    @State private var isFavorited = false
    @State private var favoriteMessage: String?
    @State private var isSnatching = false
    @State private var isRefreshing = false
    @State private var refreshError: String?
    @State private var appeared = false

    init(demand: Demand, poolMode: PoolMode = .standard) {
        self.poolMode = poolMode
        _displayDemand = State(initialValue: demand)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.space24) {
                    if let refreshError {
                        Text(refreshError)
                            .font(.caption)
                            .foregroundStyle(AppTheme.error)
                    }
                    metaBlock
                    outcomeCard
                    priceCard
                    infoCard
                    publisherCard
                }
                .padding(.horizontal, AppTheme.space24)
                .padding(.top, AppTheme.space16)
                .padding(.bottom, AppTheme.space24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)
            }

            Divider()
            applyBar
                .padding(.horizontal, AppTheme.space24)
                .padding(.vertical, AppTheme.space16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.surface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.workspaceBackground)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await refreshDemand() }
                } label: {
                    if isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await toggleFavorite() }
                } label: {
                    if isFavoriting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(isFavorited ? "已收藏" : "收藏", systemImage: isFavorited ? "heart.fill" : "heart")
                    }
                }
                .disabled(isFavoriting)
            }
        }
        .task(id: displayDemand.id) {
            await refreshDemand()
            await loadFavoriteState()
        }
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                appeared = true
            }
        }
        .onChange(of: displayDemand.id) { _, _ in
            appeared = false
            withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                appeared = true
            }
        }
        .sheet(isPresented: $showApplySheet) {
            ApplyDemandSheet { reason in
                Task { await submitApply(reason) }
            }
            .frame(minWidth: 420, minHeight: 280)
        }
        .sheet(isPresented: $showBidSheet) {
            BidDemandSheet { price, message in
                Task { await submitBid(price: price, message: message) }
            }
            .frame(minWidth: 420, minHeight: 300)
        }
        .alert("需求", isPresented: Binding(
            get: { applyMessage != nil || applyError != nil || favoriteMessage != nil },
            set: {
                if !$0 {
                    applyMessage = nil
                    applyError = nil
                    favoriteMessage = nil
                }
            }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(applyMessage ?? applyError ?? favoriteMessage ?? "")
        }
    }

    // MARK: - Blocks

    /// 详情只呈现需求信息本身；装饰性封面只出现在左侧列表作预览（类似短视频封面 vs 正片）。
    private var metaBlock: some View {
        VStack(alignment: .leading, spacing: AppTheme.space12) {
            NWStatusChip(text: displayDemand.status.title, tint: AppTheme.openStatus)

            Text(displayDemand.title)
                .font(.title.bold())
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                NWAvatarView(
                    url: displayDemand.publisher.avatarMediaURL,
                    name: displayDemand.publisher.name,
                    size: 28
                )
                Text("\(displayDemand.publisher.name) · 信用分 \(displayDemand.publisher.creditScore)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: AppTheme.space8) {
                Image(systemName: "clock")
                Text("公开剩余 \(displayDemand.countdownText)")
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(AppTheme.countdownForeground)
            .padding(.horizontal, AppTheme.space12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppTheme.countdownBackground.opacity(0.85),
                in: RoundedRectangle(cornerRadius: AppTheme.buttonRadius, style: .continuous)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var outcomeCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.space12) {
            Label("期望效果", systemImage: "checkmark.seal")
                .font(.headline)
            Text(displayDemand.expectedOutcome)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninewoodCard()
    }

    private var priceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("报价与时限")
                .font(.headline)
                .padding(AppTheme.space16)
            row("期望报价", displayDemand.expectedPrice?.currencyText ?? "—")
            Divider().padding(.leading, AppTheme.space16)
            row("最低报价限额", displayDemand.minPrice.currencyText)
            Divider().padding(.leading, AppTheme.space16)
            row("完成时限", displayDemand.deadlineText, valueColor: AppTheme.error)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninewoodCard()
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.space12) {
            Text("服务信息")
                .font(.headline)
            if !displayDemand.tags.isEmpty {
                FlowLayout(spacing: AppTheme.space8) {
                    ForEach(displayDemand.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AppTheme.fill.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }
            Label(displayDemand.distanceText + " · 位置已模糊", systemImage: "location")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(AppTheme.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninewoodCard()
    }

    private var publisherCard: some View {
        HStack(spacing: AppTheme.space12) {
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
        .padding(AppTheme.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninewoodCard()
    }

    private var applyBar: some View {
        VStack(alignment: .leading, spacing: AppTheme.space8) {
            if poolMode == .deadPool {
                Button {
                    Task { await snatch() }
                } label: {
                    Text(isSnatching ? "抢单中…" : "抢单")
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSnatching)
            } else {
                HStack(spacing: AppTheme.space12) {
                    Button {
                        showApplySheet = true
                    } label: {
                        Text("请求接单")
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!displayDemand.status.acceptsRequests)

                    Button {
                        showBidSheet = true
                    } label: {
                        Text("卡池应标")
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!displayDemand.status.acceptsRequests)
                }
            }

            Text(poolMode == .deadPool
                ? "死池抢单将直接尝试接手该需求。"
                : "请求接单用于沟通；应标用于卡池报价。二者都不等于正式接单。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ title: String, _ value: String, valueColor: Color = AppTheme.onSurface) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium).foregroundStyle(valueColor)
        }
        .font(.body)
        .padding(.horizontal, AppTheme.space16)
        .padding(.vertical, 14)
    }

    // MARK: - Actions

    private func refreshDemand() async {
        isRefreshing = true
        refreshError = nil
        defer { isRefreshing = false }
        do {
            displayDemand = try await session.demandService.getDemand(id: displayDemand.id)
        } catch {
            refreshError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadFavoriteState() async {
        do {
            let page = try await session.userService.favorites()
            isFavorited = page.demands.contains { $0.id == displayDemand.id }
        } catch {
            // 收藏态非关键路径，失败时保持默认
        }
    }

    private func toggleFavorite() async {
        isFavoriting = true
        defer { isFavoriting = false }
        do {
            try await session.userService.toggleFavorite(demandId: displayDemand.id)
            isFavorited.toggle()
            favoriteMessage = isFavorited ? "已收藏需求" : "已取消收藏"
        } catch {
            favoriteMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func snatch() async {
        isSnatching = true
        defer { isSnatching = false }
        do {
            try await session.demandService.snatch(id: displayDemand.id)
            applyMessage = "抢单成功"
            await refreshDemand()
        } catch {
            applyError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func submitApply(_ reason: String) async {
        do {
            _ = try await session.demandService.requestApply(
                id: displayDemand.id,
                message: reason,
                idempotencyKey: UUID().uuidString
            )
            applyMessage = "已提交请求接单，可等待发布者沟通"
        } catch {
            applyError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func submitBid(price: Decimal?, message: String) async {
        do {
            try await session.demandService.bid(id: displayDemand.id, offerPrice: price, message: message)
            applyMessage = "已提交应标"
        } catch {
            applyError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
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
