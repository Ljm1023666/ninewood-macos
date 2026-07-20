import AppKit
import PhotosUI
import SwiftUI

struct OrdersListView: View {
    @Environment(AppSession.self) private var session
    @State private var model: OrdersFeatureModel
    private let repository: OrderRepository
    private let previewOrders: [Order]?
    private let previewCurrentUserID: String?

    init(
        repository: OrderRepository,
        previewOrders: [Order]? = nil,
        previewCurrentUserID: String? = nil
    ) {
        self.repository = repository
        self.previewOrders = previewOrders
        self.previewCurrentUserID = previewCurrentUserID
        _model = State(initialValue: OrdersFeatureModel(
            repository: repository,
            previewOrders: previewOrders
        ))
    }

    var body: some View {
        Group {
            if previewOrders != nil {
                OrdersDesignReferencePreview(
                    model: model,
                    currentUserID: previewCurrentUserID ?? OrdersDesignPreviewFixtures.currentUserID
                )
            } else {
                liveOrdersShell
            }
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("订单")
        .toolbar {
            if previewOrders == nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("刷新") { Task { await model.load() } }
                }
            }
        }
        .task(id: model.roleFilter) {
            guard previewOrders == nil else { return }
            await model.load()
        }
    }

    private var liveOrdersShell: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                NWPaneCaption(text: "预付 · 履约 · 验收 · 结算")

                Picker("筛选", selection: $model.filter) {
                    ForEach(OrdersFeatureModel.Filter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                Picker("角色", selection: $model.roleFilter) {
                    ForEach(OrdersFeatureModel.RoleFilter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                if let loadError = model.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(loadError).foregroundStyle(.secondary)
                        Button("重新加载") { Task { await model.load() } }
                    }
                    .padding(16)
                    Spacer(minLength: 0)
                } else if model.isLoading && model.orders.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                    Spacer(minLength: 0)
                } else if model.filteredOrders.isEmpty {
                    NWEmptyState(
                        title: "暂无订单",
                        systemImage: "doc.text",
                        message: "正式接单后会出现在这里"
                    )
                    Spacer(minLength: 0)
                } else {
                    List(model.filteredOrders, selection: $model.selected) { order in
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
                if let selected = model.selected {
                    OrderDetailView(
                        order: selected,
                        currentUserID: previewCurrentUserID ?? session.currentUserId,
                        repository: repository
                    ) { updated in model.apply(updated) }
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

}

enum OrdersDesignPreviewFixtures {
    static let currentUserID = "preview-requester"
    static let provider = AppUser(
        id: "preview-provider",
        name: "思远工作室",
        avatarUrl: nil,
        coverUrl: nil,
        demandCardCoverUrl: nil,
        creditScore: 92,
        completedOrders: 46,
        goodRate: 0.99
    )

    static let orders: [Order] = [
        order(
            "01",
            "产品需求与用户反馈整理",
            .inProgress,
            "2025/05/22 14:30",
            600,
            prepaid: false,
            providerName: "思远工作室",
            requesterName: "林一"
        ),
        order("02", "品牌视觉设计交付", .inProgress, "今天 14:20", 980, prepaid: true),
        order("03", "用户访谈记录整理", .waitingReview, "昨天 18:05", 600, prepaid: true),
        order("04", "竞品功能体验报告", .completed, "7月16日", 760, prepaid: true)
    ]

    static let paymentOrder = orders[0]
    static let disputeOrder = orders[1]

    private static func order(
        _ id: String,
        _ title: String,
        _ stage: Order.Stage,
        _ submittedAt: String,
        _ amount: Decimal,
        prepaid: Bool,
        providerName: String? = nil,
        requesterName: String? = nil
    ) -> Order {
        let providerUser = providerName.map { name in
            AppUser(
                id: "preview-provider-\(id)",
                name: name,
                avatarUrl: nil,
                coverUrl: nil,
                demandCardCoverUrl: nil,
                creditScore: 92,
                completedOrders: 46,
                goodRate: 0.99
            )
        } ?? provider
        let demand = Demand(
            id: "preview-order-demand-\(id)",
            title: title,
            expectedOutcome: "按确认范围完成交付，保留过程记录，并在约定时间内提供可验收成果。",
            minPrice: amount,
            expectedPrice: amount,
            deposit: amount,
            mediaUrls: [],
            lifecycleStage: "ACTIVE",
            distanceText: "线上",
            countdownText: "3天12小时",
            applicantCount: 6,
            applicantLimit: 10,
            tags: ["产品设计", "可靠交付"],
            state: .normal,
            publisher: AppUser(
                id: currentUserID,
                name: requesterName ?? "林夏",
                avatarUrl: nil,
                coverUrl: nil,
                demandCardCoverUrl: nil,
                creditScore: 86,
                completedOrders: 23,
                goodRate: 0.98
            ),
            deadlineText: "2026-07-25 18:00",
            isCertifiedOnly: true,
            allowNearby: false,
            status: .inProgress
        )
        return Order(
            id: id == "01" ? "NW202505220001" : "preview-order-\(id)",
            demand: demand,
            provider: providerUser,
            requesterId: currentUserID,
            providerId: providerUser.id,
            stage: stage,
            rawStatus: stage == .disputed ? "DISPUTED" : "IN_PROGRESS",
            paidAt: prepaid ? "2026-07-18 13:40" : nil,
            completedAt: stage == .completed ? "2026-07-17 16:30" : nil,
            submittedAtText: submittedAt,
            dealAmount: amount,
            escrowAmount: amount,
            remainingPay: amount,
            serviceFee: amount * Decimal(string: "0.10")!,
            amountHint: "资金分项由服务端规则确认",
            amountsFromServer: true
        )
    }
}

// MARK: - Design reference (13-orders.png)

private struct OrdersDesignReferencePreview: View {
    @Bindable var model: OrdersFeatureModel
    let currentUserID: String
    @State private var rolePill: OrdersFeatureModel.RoleFilter = .all
    @State private var stageFilter = "全部阶段"

    private var selected: Order? { model.selected ?? model.orders.first }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                NWFilterPills(
                    items: [OrdersFeatureModel.RoleFilter.all, .requester, .provider],
                    selection: $rolePill
                ) { $0.rawValue.replacingOccurrences(of: "全部角色", with: "全部") }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

                HStack {
                    Spacer()
                    Menu(stageFilter) {
                        Button("全部阶段") { stageFilter = "全部阶段" }
                        Button("进行中") { stageFilter = "进行中" }
                        Button("待验收") { stageFilter = "待验收" }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryLabel)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.orders) { order in
                            previewListRow(order)
                        }
                    }
                }

                Text("共 28 条订单")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
            .paneColumn(minWidth: 300, idealWidth: 340)

            Divider()

            if let selected {
                OrdersDesignReferenceDetail(order: selected, currentUserID: currentUserID)
            } else {
                NWDetailPlaceholder(title: "选择订单", systemImage: "checklist", message: "从左侧选择一笔订单")
            }
        }
    }

    private func previewListRow(_ order: Order) -> some View {
        let isSelected = model.selected?.id == order.id
        return Button {
            model.selected = order
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(order.demand.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(order.dealAmount.pointsText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.primary)
                }
                Text("对方：\(order.provider.name)")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
                HStack {
                    Text("更新于 \(order.submittedAtText)")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.secondaryLabel)
                    Spacer()
                    Text(order.stage.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(stageTint(order.stage))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .nwSelectionChrome(isSelected: isSelected, cornerRadius: 0)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func stageTint(_ stage: Order.Stage) -> Color {
        switch stage {
        case .completed: AppTheme.openStatus
        case .waitingReview: AppTheme.secondaryLabel
        default: AppTheme.primary
        }
    }
}

private struct OrdersDesignReferenceDetail: View {
    let order: Order
    let currentUserID: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(order.demand.title)
                            .font(.system(size: 20, weight: .bold))
                        Text("订单号：\(order.id)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("创建于 2025/05/22 11:02")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                }

                stageStepper
                participantsRow
                activityChatSplit
                feeBreakdown
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppTheme.surface)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("取消订单") {}
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .disabled(true)
                    .help("设计预览不可操作")
                Spacer()
                Button {} label: {
                    Text("确认预付")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .padding(.horizontal, 24)
                        .frame(height: 42)
                        .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppTheme.buttonRadius))
                }
                .buttonStyle(.plain)
                .disabled(true)
                .help("设计预览不可预付；线上请打开真实订单详情")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(AppTheme.surface)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private var stageStepper: some View {
        HStack(alignment: .top, spacing: 0) {
            step("已接受", date: "2025/05/22 11:05", state: .done)
            stepConnector(done: true)
            step("进行中", date: "待确认预付", state: .current)
            stepConnector(done: false)
            step("待验收", date: nil, state: .upcoming)
            stepConnector(done: false)
            step("已完成", date: nil, state: .upcoming)
        }
        .padding(16)
        .ninewoodCard()
    }

    private enum StepState { case done, current, upcoming }

    private func step(_ title: String, date: String?, state: StepState) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .strokeBorder(state == .upcoming ? AppTheme.outlineVariant : AppTheme.primary, lineWidth: state == .current ? 2 : 1)
                    .background(Circle().fill(state == .done ? AppTheme.primary : Color.clear))
                    .frame(width: 22, height: 22)
                if state == .done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            Text(title)
                .font(.caption.weight(.semibold))
            if let date {
                Text(date)
                    .font(.system(size: 10))
                    .foregroundStyle(state == .current ? AppTheme.primary : .secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stepConnector(done: Bool) -> some View {
        Rectangle()
            .fill(done ? AppTheme.primary : AppTheme.outlineVariant)
            .frame(height: 2)
            .frame(maxWidth: 40)
            .padding(.top, 11)
    }

    private var participantsRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("参与方").font(.headline)
            HStack(spacing: 24) {
                partyBlock(label: "需求方（我）", name: order.demand.publisher.name, asset: "AvatarLinXia")
                partyBlock(label: "服务方", name: order.provider.name, asset: nil)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("已定金额").font(.caption).foregroundStyle(.secondary)
                    Text(order.dealAmount.pointsText).font(.title3.bold())
                    Text("约 ¥\(NSDecimalNumber(decimal: order.dealAmount).intValue).00")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                NWStatusChip(text: "托管状态：已托管", tint: AppTheme.openStatus)
                NWStatusChip(text: "服务费状态：待预付后收取", tint: AppTheme.openStatus)
            }
            Button {} label: {
                HStack(spacing: 4) {
                    Text("\(order.demand.title) (ID: DEMAND-20250522-001)")
                    Image(systemName: "arrow.up.right")
                }
                .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.secondaryLabel)
            .disabled(true)
            .help("设计预览不可打开需求链")
        }
        .padding(16)
        .ninewoodCard()
    }

    private func partyBlock(label: String, name: String, asset: String?) -> some View {
        HStack(spacing: 8) {
            Group {
                if let asset, NSImage(named: asset) != nil {
                    Image(asset).resizable().scaledToFill()
                } else {
                    Circle().fill(AppTheme.fill)
                        .overlay { Text(String(name.prefix(1))).font(.caption.weight(.semibold)) }
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(name).font(.subheadline.weight(.semibold))
            }
        }
    }

    private var activityChatSplit: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("订单动态").font(.headline)
                timelineRow("服务方已确认开始服务，等待预付", time: "2025/05/22 11:08", active: true)
                timelineRow("附言：已阅读需求说明，预计 3 个工作日完成初稿。", time: "2025/05/22 11:06", active: false)
                timelineRow("订单已创建", time: "2025/05/22 11:02", active: false)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ninewoodCard()

            VStack(alignment: .leading, spacing: 8) {
                Text("消息").font(.headline)
                chatBubble("你好，我已阅读需求说明，预计 3 个工作日完成初稿。", incoming: true)
                chatBubble("好的，预付确认后我就开始。", incoming: false)
                TextField("输入消息，Enter 发送", text: .constant(""))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ninewoodCard()
        }
    }

    private func timelineRow(_ text: String, time: String, active: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .strokeBorder(active ? AppTheme.primary : AppTheme.outlineVariant, lineWidth: active ? 0 : 1)
                .background(Circle().fill(active ? AppTheme.primary : Color.clear))
                .frame(width: 8, height: 8)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.caption)
                Text(time).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private func chatBubble(_ text: String, incoming: Bool) -> some View {
        HStack {
            if !incoming { Spacer(minLength: 20) }
            Text(text)
                .font(.caption)
                .padding(8)
                .background(incoming ? AppTheme.fill.opacity(0.5) : AppTheme.primary)
                .foregroundStyle(incoming ? Color.primary : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            if incoming { Spacer(minLength: 20) }
        }
    }

    private var feeBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("费用明细").font(.headline)
            HStack(spacing: 6) {
                Text("托管金额（总额）600 点")
                Text("-").foregroundStyle(.secondary)
                Text("服务费（10%）60 点")
                Text("=").foregroundStyle(.secondary)
                Text("服务方可得 540 点").foregroundStyle(AppTheme.openStatus)
            }
            .font(.caption)
            Text("您本次需预付 600 点（约 ¥600.00）")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primary)
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("金额来源").font(.caption.weight(.semibold))
                    Text("查看计费规则说明")
                        .font(.caption)
                        .foregroundStyle(AppTheme.primary)
                }
            }
        }
        .padding(16)
        .ninewoodCard()
    }
}

struct OrderDetailView: View {
    @State private var model: OrderDetailFeatureModel

    @State private var showSettlement = true
    @State private var showRejectSheet = false
    @State private var showReviewSheet = false
    @State private var showPartialSheet = false
    @State private var showPaymentSheet = false
    init(
        order: Order,
        currentUserID: String?,
        repository: OrderRepository,
        onUpdated: ((Order) -> Void)? = nil
    ) {
        _model = State(initialValue: OrderDetailFeatureModel(
            order: order,
            currentUserID: currentUserID,
            repository: repository,
            onUpdated: onUpdated
        ))
    }

    var body: some View {
        let order = model.order
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

                if let lastBreakdown = model.lastBreakdown {
                    breakdownCard(lastBreakdown)
                }

                DisclosureGroup("结算明细", isExpanded: $showSettlement) {
                    settleRow("成交金额", order.dealAmount.currencyText)
                    settleRow("已托管（最低保障）", order.escrowDisplayText)
                    settleRow("待支付余款", order.remainingPayDisplayText)
                    settleRow("平台服务费", order.serviceFeeDisplayText)
                    settleRow(
                        order.isPrepaid ? "验收应付（已预付服务费）" : "验收应付（含服务费）",
                        order.amountsFromServer ? order.totalDue.currencyText : "—"
                    )
                    if let paidAt = order.paidAt {
                        settleRow("预付时间", paidAt)
                    }
                    if let completedAt = order.completedAt {
                        settleRow("完成时间", completedAt)
                    }
                    if !order.amountHint.isEmpty {
                        settleRow("资金提示", order.amountHint)
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
            get: { model.actionMessage != nil },
            set: { if !$0 { model.actionMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(model.actionMessage ?? "")
        }
        .sheet(isPresented: $showPaymentSheet) {
            PaymentSheet(order: model.order) { message, updated in
                model.applyPaymentResult(message: message, updated: updated)
            }
            .frame(minWidth: 520, minHeight: 360)
        }
        .sheet(isPresented: $showRejectSheet) {
            RejectEvidenceSheet(orderId: model.order.id, order: model.order) { message in
                model.applyDisputeResult(message: message)
            }
            .frame(minWidth: 420, minHeight: 280)
        }
        .sheet(isPresented: $showReviewSheet) {
            ReviewOrderSheet(orderId: model.order.id) { message in
                model.actionMessage = message
            }
            .frame(minWidth: 420, minHeight: 300)
        }
        .sheet(isPresented: $showPartialSheet) {
            PartialCompleteSheet(order: model.order) { message, remainingId in
                Task {
                    await model.applyPartialResult(
                        message: message,
                        remainingDemandID: remainingId
                    )
                }
            }
            .frame(minWidth: 440, minHeight: 320)
        }
        .task(id: model.order.id) { await model.reload() }
    }

    @ViewBuilder
    private var actionPanel: some View {
        let order = model.order
        let actionPolicy = model.actionPolicy
        VStack(spacing: 10) {
            if actionPolicy.allowedActions.contains(.prepayServiceFee) {
                Button {
                    showPaymentSheet = true
                } label: {
                    Label("支付平台服务费（5%）", systemImage: "creditcard.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isActing)

                Text("预付仅扣除服务费；成交余款在验收时结算。托管的最低保障在发布时已锁定。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if actionPolicy.allowedActions.contains(.markComplete) {
                Button {
                    Task { await model.complete() }
                } label: {
                    Label(model.isActing ? "处理中…" : "标记服务完成", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isActing)

                if actionPolicy.allowedActions.contains(.completePartially) {
                    Button("部分完成并结算") { showPartialSheet = true }
                        .disabled(model.isActing)
                }
            }

            // 服务方提示：等待预付
            if model.isProvider, order.stage == .inProgress, !order.isPrepaid {
                Text("等待需求方预付平台服务费后，方可标记完成。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .ninewoodCard()
            }

            if actionPolicy.allowedActions.contains(.confirmAndSettle) {
                Button {
                    Task {
                        if await model.confirm() {
                            showReviewSheet = true
                        }
                    }
                } label: {
                    Label(model.isActing ? "结算中…" : "确认完成并付款", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isActing)

                if actionPolicy.allowedActions.contains(.dispute) {
                    Button("提交争议") { showRejectSheet = true }
                        .foregroundStyle(AppTheme.error)
                        .disabled(model.isActing)
                }
            }

            if actionPolicy.allowedActions.contains(.cancel) {
                Button(role: .destructive) {
                    Task { await model.cancel() }
                } label: {
                    Text(model.isActing ? "取消中…" : "取消订单")
                        .frame(maxWidth: .infinity)
                }
                .disabled(model.isActing)
            }

            if actionPolicy.allowedActions.contains(.review) {
                Button("评价本次服务") { showReviewSheet = true }
                    .buttonStyle(.bordered)
            }

            Button("刷新订单状态") {
                Task { await model.reload() }
            }
            .disabled(model.isActing)
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

/// 服务费预付确认弹层（对齐 ui-renderings/26）。
/// - `designPreviewOnly`：静态稿，不请求后端
/// - 默认：必须先拉 `pay-breakdown`，再 `prepay`；无分项禁止确认
struct PaymentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    let order: Order
    var designPreviewOnly: Bool = false
    var onDone: (String, Order?) -> Void

    @State private var modalModel: PaymentPrepayModalModel
    @State private var showsRetryBanner: Bool
    @State private var isLoadingPreview = false
    @State private var isConfirming = false
    @State private var breakdownReady = false
    @State private var loadError: String?

    init(
        order: Order,
        previewBreakdown: OrderPayBreakdownDTO? = nil,
        previewBalance: Decimal? = nil,
        designPreviewOnly: Bool = false,
        onDone: @escaping (String, Order?) -> Void
    ) {
        self.order = order
        self.designPreviewOnly = designPreviewOnly
        self.onDone = onDone
        if let previewBreakdown {
            let seed = Self.model(
                order: order,
                breakdown: previewBreakdown,
                balance: previewBalance ?? 1000
            )
            _modalModel = State(initialValue: seed)
            _showsRetryBanner = State(initialValue: true)
            _breakdownReady = State(initialValue: true)
        } else if designPreviewOnly {
            _modalModel = State(initialValue: .designFixture)
            _showsRetryBanner = State(initialValue: true)
            _breakdownReady = State(initialValue: true)
        } else {
            _modalModel = State(initialValue: Self.placeholderModel(order: order))
            _showsRetryBanner = State(initialValue: false)
            _breakdownReady = State(initialValue: false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let loadError, !designPreviewOnly {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(AppTheme.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
            }
            PaymentPrepayModal(
                model: $modalModel,
                showsRetryBanner: showsRetryBanner || (!breakdownReady && !designPreviewOnly),
                isLoadingPreview: isLoadingPreview,
                isConfirming: isConfirming,
                confirmEnabled: designPreviewOnly || breakdownReady,
                onCancel: { dismiss() },
                onConfirm: {
                    if designPreviewOnly {
                        onDone("服务费 \(modalModel.serviceFee.currencyText) 已扣除（设计预览）", nil)
                        dismiss()
                    } else {
                        Task { await confirmPrepay() }
                    }
                },
                onRetryPreview: {
                    Task { await loadPreview() }
                },
                onClose: { dismiss() }
            )
        }
        .frame(minWidth: 520, idealWidth: 520)
        .padding(12)
        .background(AppTheme.groupedBackground)
        .task {
            guard !designPreviewOnly, !breakdownReady else { return }
            await loadPreview()
        }
    }

    private func loadPreview() async {
        isLoadingPreview = true
        loadError = nil
        defer { isLoadingPreview = false }
        do {
            async let breakdownTask = session.orderRepository.payBreakdown(id: order.id)
            async let balanceTask = session.walletService.summary()
            let breakdown = try await breakdownTask
            let balance = (try? await balanceTask)?.balance.value ?? 0
            if breakdown.alreadyPrepaid == true {
                loadError = "该订单已完成服务费预付"
                showsRetryBanner = true
                breakdownReady = false
                return
            }
            guard breakdown.payableNow?.value != nil || breakdown.serviceFee?.value != nil else {
                loadError = "无法获取预付分项，请重试"
                showsRetryBanner = true
                breakdownReady = false
                return
            }
            modalModel = Self.model(order: order, breakdown: breakdown, balance: balance)
            showsRetryBanner = false
            breakdownReady = true
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showsRetryBanner = true
            breakdownReady = false
        }
    }

    private func confirmPrepay() async {
        guard breakdownReady, !isConfirming else { return }
        isConfirming = true
        defer { isConfirming = false }
        do {
            let result = try await session.orderRepository.prepay(id: order.id)
            let updated = try? await session.orderRepository.detail(id: order.id)
            let feeText = (result.serviceFee?.value ?? result.amount?.value ?? modalModel.serviceFee).currencyText
            onDone(result.message ?? "服务费 \(feeText) 已扣除", updated)
            dismiss()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showsRetryBanner = true
        }
    }

    private static func placeholderModel(order: Order) -> PaymentPrepayModalModel {
        PaymentPrepayModalModel(
            orderCode: order.id,
            demandTitle: order.demand.title,
            requesterName: order.demand.publisher.name,
            providerName: order.provider.name,
            agreedAmount: order.dealAmount,
            escrowAmount: order.escrowAmount,
            feeRate: Decimal(string: "0.05") ?? 0.05,
            serviceFee: 0,
            balance: 0,
            ruleVersion: "—",
            agreedChecked: false
        )
    }

    private static func model(
        order: Order,
        breakdown: OrderPayBreakdownDTO,
        balance: Decimal
    ) -> PaymentPrepayModalModel {
        let agreed = breakdown.agreedPrice?.value ?? order.dealAmount
        let feeRate = Decimal(breakdown.serviceFeeRate ?? 0.05)
        let fee = breakdown.payableNow?.value ?? breakdown.serviceFee?.value ?? 0
        return PaymentPrepayModalModel(
            orderCode: order.id,
            demandTitle: order.demand.title,
            requesterName: order.demand.publisher.name,
            providerName: order.provider.name,
            agreedAmount: agreed,
            escrowAmount: breakdown.escrowHeld?.value
                ?? breakdown.depositRequired?.value
                ?? order.escrowAmount,
            feeRate: feeRate,
            serviceFee: fee,
            balance: balance,
            ruleVersion: breakdown.ruleVersion ?? "—",
            agreedChecked: true
        )
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
            let result = try await session.orderRepository.completePartially(
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
    @State private var errorMessage: String?

    private let ratingHints = [
        1: "很不满意",
        2: "不太满意",
        3: "一般",
        4: "比较满意",
        5: "非常满意",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("评价服务").font(.title2.bold())
            Text("为本次服务给出总体评分")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        rating = star
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(star <= rating ? Color.orange : AppTheme.secondaryLabel)
                    }
                    .buttonStyle(.plain)
                    .help("\(star) 星")
                }
                Text(ratingHints[rating] ?? "")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.onSurface)
                    .padding(.leading, 4)
            }

            TextEditor(text: $content)
                .font(.body)
                .frame(minHeight: 100)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(AppTheme.fill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("可选：服务是否如约、沟通是否顺畅…")
                            .font(.body)
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.error)
            }

            HStack {
                Button("稍后再说") { dismiss() }
                Spacer()
                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("提交评价")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
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
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// 订单争议 / 证据提交（渲染图 25）。
/// - `designPreview == true`：静态稿
/// - 默认：真实上传证据 + `POST /orders/:id/dispute`
struct RejectEvidenceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    let orderId: String
    var orderTitle: String
    var requesterName: String
    var providerName: String
    var amountText: String
    var designPreview: Bool
    var onDone: (String) -> Void

    @State private var reason: String
    @State private var evidenceURLDraft = ""
    @State private var evidenceLink: String?
    @State private var imageSlots: [DisputeEvidenceImage]
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var agreed = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var uploadedCount = 0

    init(
        orderId: String,
        order: Order? = nil,
        designPreview: Bool = false,
        onDone: @escaping (String) -> Void
    ) {
        self.orderId = orderId
        self.designPreview = designPreview
        self.onDone = onDone
        if designPreview {
            self.orderTitle = DisputeDesignFixtures.orderTitle
            self.requesterName = DisputeDesignFixtures.requesterName
            self.providerName = DisputeDesignFixtures.providerName
            self.amountText = DisputeDesignFixtures.amountText
            _reason = State(initialValue: "交付内容与确认范围不一致，过程记录中的验收标准与最终交付件存在多处差异，需要平台协助核对沟通记录与交付版本。")
            _imageSlots = State(initialValue: DisputeDesignFixtures.previewImages)
            _evidenceLink = State(initialValue: "https://evidence.ninewood.example/delivery-comparison.pdf")
        } else {
            self.orderTitle = order?.demand.title ?? "订单争议"
            self.requesterName = order?.demand.publisher.name ?? "需求方"
            self.providerName = order?.provider.name ?? "服务方"
            let amount = order?.dealAmount ?? 0
            self.amountText = "\(NSDecimalNumber(decimal: amount).stringValue) 点"
            _reason = State(initialValue: "")
            _imageSlots = State(initialValue: [])
            _evidenceLink = State(initialValue: nil)
        }
    }

    private var canSubmit: Bool {
        !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && agreed && !isSubmitting
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    orderSummary
                    reasonSection
                    imagesSection
                    linkSection
                    uploadStatus
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.error)
                    }
                    privacyNotice
                    agreementRow
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 28, y: 14)
        .onChange(of: photoItems) { _, items in
            guard !designPreview else { return }
            Task { await ingestPhotos(items) }
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            Text("提交争议")
                .font(.system(size: 17, weight: .bold))
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.fill.opacity(0.7), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var orderSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(orderTitle)
                .font(.system(size: 14, weight: .semibold))
            Text("订单号 \(orderId)")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryLabel)

            HStack(spacing: 20) {
                party(
                    label: "需求方",
                    name: requesterName,
                    asset: designPreview ? "AvatarLinXia" : nil
                )
                party(
                    label: "服务方",
                    name: providerName,
                    asset: designPreview ? "AvatarChenShu" : nil
                )
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("已定金额")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                    Text(amountText)
                        .font(.system(size: 15, weight: .bold))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceLow, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func party(label: String, name: String, asset: String?) -> some View {
        HStack(spacing: 8) {
            Group {
                if let asset, NSImage(named: asset) != nil {
                    Image(asset).resizable().scaledToFill()
                } else {
                    Circle()
                        .fill(AppTheme.fill)
                        .overlay {
                            Text(String(name.prefix(1)))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppTheme.primary)
                        }
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.secondaryLabel)
                Text(name)
                    .font(.system(size: 12, weight: .medium))
            }
        }
    }

    private var reasonSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 2) {
                Text("争议原因")
                    .font(.system(size: 13, weight: .semibold))
                Text("*")
                    .foregroundStyle(AppTheme.error)
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $reason)
                    .font(.system(size: 13))
                    .frame(minHeight: 96)
                    .scrollContentBackground(.hidden)
                if reason.isEmpty {
                    Text("请说明争议原因，便于平台核对过程记录…")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.secondaryLabel.opacity(0.7))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(10)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
            }

            HStack {
                Spacer()
                Text("\(min(reason.count, 500))/500")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
        }
        .onChange(of: reason) { _, value in
            if value.count > 500 {
                reason = String(value.prefix(500))
            }
        }
    }

    private var imagesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("图片证据")
                    .font(.system(size: 13, weight: .semibold))
                Text("（可选，最多 6 张）")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }

            HStack(spacing: 10) {
                ForEach(Array(imageSlots.enumerated()), id: \.element.id) { index, slot in
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(slot.tint.opacity(0.18))
                            .overlay {
                                if let data = slot.localData, let nsImage = NSImage(data: data) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Image(systemName: slot.symbol)
                                        .font(.system(size: 22))
                                        .foregroundStyle(slot.tint)
                                }
                            }
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        Button {
                            imageSlots.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(AppTheme.secondaryLabel)
                                .background(Circle().fill(AppTheme.surface))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 4, y: -4)
                    }
                }

                if imageSlots.count < 6 {
                    if designPreview {
                        Button {
                            let next = DisputeDesignFixtures.nextImage(after: imageSlots.count)
                            imageSlots.append(next)
                        } label: {
                            addImagePlaceholder
                        }
                        .buttonStyle(.plain)
                    } else {
                        PhotosPicker(selection: $photoItems, maxSelectionCount: 6 - imageSlots.count, matching: .images) {
                            addImagePlaceholder
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var addImagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(AppTheme.outlineVariant, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            .frame(width: 72, height: 72)
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
    }

    private var linkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("证据链接")
                    .font(.system(size: 13, weight: .semibold))
                Text("（可选）")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }

            HStack(spacing: 8) {
                TextField("请输入网页链接（如网盘链接、文档链接等）", text: $evidenceURLDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                    }

                Button("添加") {
                    let trimmed = evidenceURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    evidenceLink = trimmed
                    evidenceURLDraft = ""
                }
                .buttonStyle(.bordered)
            }

            if let evidenceLink {
                HStack {
                    Text(evidenceLink)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .lineLimit(1)
                    Spacer()
                    Button("移除") { self.evidenceLink = nil }
                        .buttonStyle(.borderless)
                        .foregroundStyle(AppTheme.error)
                }
            }
        }
    }

    private var uploadStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("上传状态：")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryLabel)
                if designPreview {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.openStatus)
                    Text("\(imageSlots.count)/\(max(imageSlots.count, 3)) 上传成功")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.openStatus)
                } else if uploadedCount > 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.openStatus)
                    Text("\(uploadedCount) 张已上传")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.openStatus)
                } else {
                    Text(imageSlots.isEmpty ? "尚未选择图片" : "将在提交时上传")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
            }
            Text("支持 jpg / png / gif / webp，单张不超过 10MB")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryLabel)
        }
    }

    private var privacyNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryLabel)
                .padding(.top, 2)
            Text("提交的证据仅用于平台调解本笔订单争议。工作人员会在合理范围内核验材料，并尽量保持双方过程记录的公平可读。")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(AppTheme.surfaceLow, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var agreementRow: some View {
        Button {
            agreed.toggle()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: agreed ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundStyle(agreed ? AppTheme.primary : AppTheme.secondaryLabel)
                Text("我已仔细阅读并同意以上说明，提交的内容真实有效")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.onSurface)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Text("取消")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.onSurface)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    )
            }
            .buttonStyle(.plain)

            Button {
                if designPreview {
                    isSubmitting = true
                    onDone(imageSlots.isEmpty && evidenceLink == nil ? "争议原因已提交" : "争议与证据已提交")
                    dismiss()
                } else {
                    Task { await submitLive() }
                }
            } label: {
                Text(isSubmitting ? "提交中…" : "提交争议")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        (canSubmit ? AppTheme.error : AppTheme.error.opacity(0.45)),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func ingestPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard imageSlots.count < 6 else { break }
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let name = "evidence-\(imageSlots.count + 1).jpg"
            imageSlots.append(
                DisputeEvidenceImage(
                    id: UUID().uuidString,
                    symbol: "photo",
                    tintKey: "primary",
                    localData: data,
                    fileName: name,
                    mimeType: "image/jpeg"
                )
            )
        }
        photoItems = []
    }

    private func submitLive() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            var urls: [String] = []
            uploadedCount = 0
            for slot in imageSlots {
                if let existing = slot.remoteURL {
                    urls.append(existing)
                    uploadedCount += 1
                    continue
                }
                guard let data = slot.localData else { continue }
                let uploaded = try await session.orderRepository.uploadEvidence(
                    fileData: data,
                    fileName: slot.fileName ?? "evidence.jpg",
                    mimeType: slot.mimeType ?? "image/jpeg"
                )
                urls.append(uploaded.url)
                uploadedCount += 1
            }
            if let evidenceLink {
                urls.append(evidenceLink)
            }
            try await session.orderRepository.dispute(
                id: orderId,
                reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
                evidenceUrls: urls
            )
            onDone(urls.isEmpty ? "争议原因已提交" : "争议与证据已提交")
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct DisputeEvidenceImage: Identifiable, Hashable {
    let id: String
    let symbol: String
    /// 避免 `Color` 进入 Hashable 合成（部分 SDK 下会触发访问控制错误）。
    let tintKey: String
    var localData: Data? = nil
    var remoteURL: String? = nil
    var fileName: String? = nil
    var mimeType: String? = nil

    var tint: Color {
        switch tintKey {
        case "secondary": AppTheme.secondary
        case "urgent": AppTheme.urgent
        case "open": AppTheme.openStatus
        case "human": AppTheme.human
        default: AppTheme.primary
        }
    }

    static func == (lhs: DisputeEvidenceImage, rhs: DisputeEvidenceImage) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum DisputeDesignFixtures {
    static let orderTitle = "产品需求与用户反馈整理"
    static let orderNo = "NW202505220001"
    static let requesterName = "林一"
    static let providerName = "思远工作室"
    static let amountText = "600 点"

    static let previewImages: [DisputeEvidenceImage] = [
        DisputeEvidenceImage(id: "img-1", symbol: "bubble.left.and.bubble.right.fill", tintKey: "primary"),
        DisputeEvidenceImage(id: "img-2", symbol: "doc.text.image.fill", tintKey: "secondary"),
        DisputeEvidenceImage(id: "img-3", symbol: "photo.on.rectangle.angled", tintKey: "urgent")
    ]

    static func nextImage(after count: Int) -> DisputeEvidenceImage {
        let palette = [
            DisputeEvidenceImage(id: "img-\(count + 1)-a", symbol: "text.bubble.fill", tintKey: "primary"),
            DisputeEvidenceImage(id: "img-\(count + 1)-b", symbol: "doc.on.doc.fill", tintKey: "open"),
            DisputeEvidenceImage(id: "img-\(count + 1)-c", symbol: "camera.fill", tintKey: "human")
        ]
        return palette[count % palette.count]
    }
}

struct TransactionSheetDesignPreview: View {
    enum Kind {
        case dispute
        case payment
    }

    let kind: Kind

    var body: some View {
        switch kind {
        case .payment:
            PaymentPrepayDesignPreview()
        case .dispute:
            ZStack {
                DisputeOrdersBackdrop()
                    .allowsHitTesting(false)

                Color.black.opacity(0.28)
                    .ignoresSafeArea()

                RejectEvidenceSheet(
                    orderId: OrdersDesignPreviewFixtures.disputeOrder.id,
                    order: OrdersDesignPreviewFixtures.disputeOrder,
                    designPreview: true
                ) { _ in }
                .frame(width: 560, height: 680)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 28, y: 14)
            }
            .navigationTitle("订单争议")
        }
    }
}

/// 渲染图 25 背景：订单列表与详情的弱化衬底。
private struct DisputeOrdersBackdrop: View {
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("全部")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppTheme.primary, in: Capsule())
                    Text("我是需求方")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryLabel)
                    Text("我是服务方")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryLabel)
                    Spacer()
                    Text("全部阶段 ▾")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                ForEach(DisputeDesignFixtures.backdropOrders, id: \.title) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.title)
                            .font(.system(size: 13, weight: .semibold))
                        Text("对方：\(row.peer)")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Text(row.time)
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .nwSelectionChrome(isSelected: row.selected, cornerRadius: 0)
                    .overlay(alignment: .bottom) {
                        Divider()
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: 300)
            .background(AppTheme.workspaceBackground)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text(DisputeDesignFixtures.orderTitle)
                    .font(.system(size: 18, weight: .bold))
                Text("待验收 → 已完成")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryLabel)
                Text("已定金额 \(DisputeDesignFixtures.amountText)")
                    .font(.system(size: 14, weight: .semibold))
                Text("约 ¥600.00")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryLabel)
                Spacer(minLength: 0)
                HStack {
                    Text("取消订单")
                        .foregroundStyle(AppTheme.error)
                    Spacer()
                    Text("确认预付")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AppTheme.surface)
        }
        .background(AppTheme.groupedBackground)
    }
}

private extension DisputeDesignFixtures {
    static let backdropOrders: [(title: String, peer: String, time: String, selected: Bool)] = [
        ("产品需求与用户反馈整理", "思远工作室", "2025/05/22 14:30", true),
        ("品牌视觉设计交付", "周屿", "今天 14:20", false),
        ("用户访谈记录整理", "程野", "昨天 18:05", false)
    ]
}
