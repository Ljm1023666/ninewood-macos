import SwiftUI

struct OrdersListView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "全部"
        case inProgress = "进行中"
        case waiting = "待验收"
        case completed = "已完成"
        case disputed = "争议"
        var id: String { rawValue }
    }

    enum RoleFilter: String, CaseIterable, Identifiable {
        case all = "全部角色"
        case requester = "我是需求方"
        case provider = "我是服务方"
        var id: String { rawValue }
        var apiRole: String? {
            switch self {
            case .all: nil
            case .requester: "requester"
            case .provider: "provider"
            }
        }
    }

    @Environment(AppSession.self) private var session
    @State private var filter: Filter = .all
    @State private var roleFilter: RoleFilter = .all
    @State private var orders: [Order] = []
    @State private var selected: Order?
    @State private var isLoading = false
    @State private var loadError: String?

    private var filteredOrders: [Order] {
        switch filter {
        case .all: orders
        case .inProgress: orders.filter { $0.stage == .inProgress || $0.stage == .accepted }
        case .waiting: orders.filter { $0.stage == .waitingReview }
        case .completed: orders.filter { $0.stage == .completed }
        case .disputed: orders.filter { $0.stage == .disputed }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                NWPaneCaption(text: "预付 · 履约 · 验收 · 结算")

                Picker("筛选", selection: $filter) {
                    ForEach(Filter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                Picker("角色", selection: $roleFilter) {
                    ForEach(RoleFilter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                if let loadError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(loadError).foregroundStyle(.secondary)
                        Button("重新加载") { Task { await loadOrders() } }
                    }
                    .padding(16)
                    Spacer(minLength: 0)
                } else if isLoading && orders.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                    Spacer(minLength: 0)
                } else if filteredOrders.isEmpty {
                    NWEmptyState(
                        title: "暂无订单",
                        systemImage: "doc.text",
                        message: "正式接单后会出现在这里"
                    )
                    Spacer(minLength: 0)
                } else {
                    List(filteredOrders, selection: $selected) { order in
                        orderCard(order)
                            .tag(order)
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                }
            }
            .paneColumn(minWidth: 320, idealWidth: 400)

            Divider()

            Group {
                if let selected {
                    OrderDetailView(order: selected) { updated in
                        if let idx = orders.firstIndex(where: { $0.id == updated.id }) {
                            orders[idx] = updated
                        }
                        self.selected = updated
                    }
                } else {
                    NWDetailPlaceholder(
                        title: "选择订单",
                        systemImage: "checklist",
                        message: "从左侧选择一笔订单查看详情与结算"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("订单")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("刷新") { Task { await loadOrders() } }
            }
        }
        .task(id: roleFilter) { await loadOrders() }
    }

    private func orderCard(_ order: Order) -> some View {
        HStack(alignment: .top, spacing: 10) {
            NWAvatarView(
                url: order.provider.avatarMediaURL,
                name: order.provider.name,
                size: 40
            )
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    NWStatusChip(text: order.stage.title)
                    if order.isPrepaid {
                        NWStatusChip(text: "已预付")
                    }
                    Spacer()
                    Text(order.dealAmount.currencyText)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(AppTheme.primary)
                }
                Text(order.demand.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                HStack {
                    Text(order.provider.name)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(order.submittedAtText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    private func loadOrders() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            orders = try await session.orderService.list(role: roleFilter.apiRole)
            if let sel = selected, let match = orders.first(where: { $0.id == sel.id }) {
                selected = match
            } else {
                selected = orders.first
            }
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct OrderDetailView: View {
    @Environment(AppSession.self) private var session
    @State private var order: Order
    var onUpdated: ((Order) -> Void)?

    @State private var showSettlement = true
    @State private var showRejectSheet = false
    @State private var showReviewSheet = false
    @State private var showPartialSheet = false
    @State private var showPaymentSheet = false
    @State private var isActing = false
    @State private var actionMessage: String?
    @State private var lastBreakdown: SettlementBreakdownDTO?

    init(order: Order, onUpdated: ((Order) -> Void)? = nil) {
        _order = State(initialValue: order)
        self.onUpdated = onUpdated
    }

    private var myId: String? { session.currentUserId }
    private var isRequester: Bool {
        guard let myId else { return false }
        if let rid = order.requesterId { return rid == myId }
        return order.demand.publisher.id == myId
    }
    private var isProvider: Bool {
        guard let myId else { return false }
        if let pid = order.providerId { return pid == myId }
        return order.provider.id == myId
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(order.demand.title)
                    .font(.title2.bold())
                HStack(spacing: 8) {
                    Text(order.stage.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                    if order.isPrepaid {
                        NWStatusChip(text: "服务费已预付")
                    }
                    if order.rawStatus.uppercased() == "CANCELLED" {
                        NWStatusChip(text: "已取消")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("期望效果").font(.headline)
                    Text(order.demand.expectedOutcome)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .ninewoodCard()

                HStack(spacing: 12) {
                    NWAvatarView(
                        url: order.provider.avatarMediaURL,
                        name: order.provider.name,
                        size: 48
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("服务方").font(.caption).foregroundStyle(.secondary)
                        Text(order.provider.name).font(.headline)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("成交价").font(.caption).foregroundStyle(.secondary)
                        Text(order.dealAmount.currencyText)
                            .font(.title3.bold())
                            .foregroundStyle(AppTheme.primary)
                    }
                }
                .padding(16)
                .ninewoodCard()

                actionPanel

                if let lastBreakdown {
                    breakdownCard(lastBreakdown)
                }

                DisclosureGroup("结算明细", isExpanded: $showSettlement) {
                    settleRow("成交金额", order.dealAmount.currencyText)
                    settleRow("已托管（最低保障）", order.escrowAmount.currencyText)
                    settleRow("待支付余款", order.remainingPay.currencyText)
                    settleRow("平台服务费（5%）", order.serviceFee.currencyText)
                    settleRow(
                        order.isPrepaid ? "验收应付（已预付服务费）" : "验收应付（含服务费）",
                        order.totalDue.currencyText
                    )
                    if let paidAt = order.paidAt {
                        settleRow("预付时间", paidAt)
                    }
                    if let completedAt = order.completedAt {
                        settleRow("完成时间", completedAt)
                    }
                }
                .padding(16)
                .ninewoodCard()
            }
            .padding(AppTheme.horizontalPadding)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .background(AppTheme.workspaceBackground)
        .alert("订单", isPresented: Binding(
            get: { actionMessage != nil },
            set: { if !$0 { actionMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(actionMessage ?? "")
        }
        .sheet(isPresented: $showPaymentSheet) {
            PaymentSheet(order: order) { message, updated in
                if let updated {
                    order = updated
                    onUpdated?(updated)
                }
                actionMessage = message
            }
            .frame(minWidth: 520, minHeight: 360)
        }
        .sheet(isPresented: $showRejectSheet) {
            RejectEvidenceSheet(orderId: order.id) { message in
                if !message.contains("失败") && !message.contains("错误") && !message.contains("未登录") {
                    order.stage = .disputed
                    order.rawStatus = "DISPUTED"
                    onUpdated?(order)
                }
                actionMessage = message.isEmpty ? "已提交争议" : message
            }
            .frame(minWidth: 420, minHeight: 280)
        }
        .sheet(isPresented: $showReviewSheet) {
            ReviewOrderSheet(orderId: order.id) { message in
                actionMessage = message
            }
            .frame(minWidth: 420, minHeight: 300)
        }
        .sheet(isPresented: $showPartialSheet) {
            PartialCompleteSheet(order: order) { message, remainingId in
                if let remainingId {
                    actionMessage = "\(message)（余量需求 \(remainingId)）"
                } else {
                    actionMessage = message
                }
                Task { await reload() }
            }
            .frame(minWidth: 440, minHeight: 320)
        }
        .task(id: order.id) { await reload() }
    }

    @ViewBuilder
    private var actionPanel: some View {
        VStack(spacing: 10) {
            // 需求方：进行中且未预付 → 支付服务费
            if isRequester, order.stage == .inProgress, !order.isPrepaid,
               order.rawStatus.uppercased() != "CANCELLED" {
                Button {
                    showPaymentSheet = true
                } label: {
                    Label("支付平台服务费（5%）", systemImage: "creditcard.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isActing)

                Text("预付仅扣除服务费；成交余款在验收时结算。托管的最低保障在发布时已锁定。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 服务方：进行中且已预付 → 标记完成 / 部分完成
            if isProvider, order.stage == .inProgress, order.isPrepaid {
                Button {
                    Task { await completeOrder() }
                } label: {
                    Label(isActing ? "处理中…" : "标记服务完成", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isActing)

                Button("部分完成并结算") { showPartialSheet = true }
                    .disabled(isActing)
            }

            // 服务方提示：等待预付
            if isProvider, order.stage == .inProgress, !order.isPrepaid {
                Text("等待需求方预付平台服务费后，方可标记完成。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .ninewoodCard()
            }

            // 需求方：待验收
            if isRequester, order.stage == .waitingReview {
                Button {
                    Task { await confirmOrder() }
                } label: {
                    Label(isActing ? "结算中…" : "确认完成并付款", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isActing)

                Button("拒绝并提交证据") { showRejectSheet = true }
                    .foregroundStyle(AppTheme.error)
                    .disabled(isActing)
            }

            // 需求方：进行中可取消
            if isRequester, order.stage == .inProgress,
               order.rawStatus.uppercased() != "CANCELLED" {
                Button(role: .destructive) {
                    Task { await cancelOrder() }
                } label: {
                    Text(isActing ? "取消中…" : "取消订单")
                        .frame(maxWidth: .infinity)
                }
                .disabled(isActing)
            }

            if order.stage == .completed {
                Button("评价本次服务") { showReviewSheet = true }
                    .buttonStyle(.bordered)
            }

            Button("刷新订单状态") {
                Task { await reload() }
            }
            .disabled(isActing)
        }
    }

    private func breakdownCard(_ b: SettlementBreakdownDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本次结算结果").font(.headline)
            settleRow("最终成交", (b.finalPrice?.value ?? 0).currencyText)
            settleRow("服务费", (b.serviceFee?.value ?? 0).currencyText)
            settleRow("需求方实付", (b.demanderPaid?.value ?? 0).currencyText)
            settleRow("服务方实收", (b.providerReceived?.value ?? 0).currencyText)
            settleRow("平台收入", (b.platformRevenue?.value ?? 0).currencyText)
            settleRow("退还托管", (b.depositReturned?.value ?? 0).currencyText)
        }
        .padding(16)
        .ninewoodCard()
    }

    private func reload() async {
        do {
            let fresh = try await session.orderService.get(id: order.id)
            order = fresh
            onUpdated?(fresh)
        } catch {
            // keep current
        }
    }

    private func completeOrder() async {
        isActing = true
        defer { isActing = false }
        do {
            try await session.orderService.complete(id: order.id)
            await reload()
            actionMessage = "已标记完成，等待需求方验收"
        } catch {
            actionMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func confirmOrder() async {
        isActing = true
        defer { isActing = false }
        do {
            let result = try await session.orderService.confirm(id: order.id)
            lastBreakdown = result.breakdown
            await reload()
            actionMessage = result.message ?? "已确认完成并结算"
            showReviewSheet = true
        } catch {
            actionMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func cancelOrder() async {
        isActing = true
        defer { isActing = false }
        do {
            try await session.orderService.cancel(id: order.id)
            await reload()
            actionMessage = "订单已取消" + (order.isPrepaid ? "（已预付服务费将按规则退还）" : "")
        } catch {
            actionMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func settleRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }
}

/// 对齐 Windows `/payment/:id` — 点数钱包预付 5% 服务费
struct PaymentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    let order: Order
    var onDone: (String, Order?) -> Void

    @State private var balance: Decimal?
    @State private var isPaying = false
    @State private var paid = false
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Label("订单摘要", systemImage: "doc.text")
                    .font(.title2.bold())
                Text("订单号 \(order.id)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(order.demand.title)
                    .font(.headline)
                settle("支付方式", "点数钱包")
                settle("成交金额", order.dealAmount.currencyText)
                settle("已托管", order.escrowAmount.currencyText)
                settle("本次预付（服务费 5%）", order.serviceFee.currencyText)
                Text("开发期 1 点 = 1 元。确认后仅扣除平台服务费；验收时再结算余款。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AppTheme.surface.opacity(0.5))

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                if paid {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(AppTheme.openStatus)
                    Text("支付成功").font(.title.bold())
                    Text("服务费已扣除，可返回订单继续履约。")
                        .foregroundStyle(.secondary)
                    Button("完成") { dismiss() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Text("确认支付").font(.title2.bold())
                    if let balance {
                        Text("当前余额 \(balance.pointsText)")
                            .foregroundStyle(.secondary)
                    }
                    Text("将扣除 \(order.serviceFee.currencyText)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(AppTheme.error)
                    }
                    Spacer()
                    HStack {
                        Button("取消") { dismiss() }
                        Spacer()
                        Button {
                            Task { await pay() }
                        } label: {
                            Text(isPaying ? "处理中…" : "确认支付")
                                .frame(minWidth: 100)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isPaying)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task {
            if let s = try? await session.walletService.summary() {
                balance = s.balance.value
            }
        }
    }

    private func settle(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.subheadline)
    }

    private func pay() async {
        isPaying = true
        errorMessage = nil
        defer { isPaying = false }
        do {
            let result = try await session.orderService.prepay(id: order.id)
            let updated = try? await session.orderService.get(id: order.id)
            paid = true
            let fee = result.serviceFee?.value ?? order.serviceFee
            onDone(result.message ?? "服务费 \(fee.currencyText) 已扣除", updated)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct PartialCompleteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    let order: Order
    var onDone: (String, String?) -> Void

    @State private var newPrice = ""
    @State private var description = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("部分完成").font(.title2.bold())
            Text("按已完成部分结算，剩余金额将生成新需求。成交价上限 \(order.dealAmount.currencyText)。")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("已完成部分金额", text: $newPrice)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $description)
                .frame(minHeight: 100)
                .padding(8)
                .background(AppTheme.fill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(AppTheme.error)
            }
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("确认部分结算") {
                    Task { await submit() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting || Decimal(string: newPrice) == nil || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
    }

    private func submit() async {
        guard let price = Decimal(string: newPrice) else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let result = try await session.orderService.partial(
                id: order.id,
                newPrice: price,
                description: description.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            onDone(result.message ?? "部分结算完成", result.remainingDemandId)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct ReviewOrderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    let orderId: String
    var onDone: (String) -> Void
    @State private var rating = 5
    @State private var content = ""
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("评价服务").font(.title2.bold())
            Stepper("评分：\(rating) 星", value: $rating, in: 1...5)
            TextEditor(text: $content)
                .frame(minHeight: 100)
                .padding(8)
                .background(AppTheme.fill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("提交评价") {
                    Task { await submit() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting)
            }
        }
        .padding(24)
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await session.reviewService.create(
                orderId: orderId,
                rating: rating,
                content: content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : content.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            onDone("评价已提交")
            dismiss()
        } catch {
            onDone((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            dismiss()
        }
    }
}

private struct RejectEvidenceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    let orderId: String
    var onDone: (String) -> Void
    @State private var reason = ""
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("拒绝付款").font(.title2.bold())
            Text("拒绝付款需要提供证据，平台将据此调解。")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $reason)
                .frame(minHeight: 100)
                .padding(8)
                .background(AppTheme.fill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("提交争议", role: .destructive) {
                    Task { await submit() }
                }
                .disabled(reason.isEmpty || isSubmitting)
            }
        }
        .padding(24)
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await session.orderService.dispute(id: orderId, reason: reason)
            onDone("争议已提交")
            dismiss()
        } catch {
            onDone((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            dismiss()
        }
    }
}
