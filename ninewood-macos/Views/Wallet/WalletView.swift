import SwiftUI

struct WalletView: View {
    @Environment(AppSession.self) private var session
    @State private var summary: WalletSummaryDTO?
    @State private var txns: [WalletTxn] = []
    @State private var ledgerItems: [WalletLedgerItemDTO] = []
    @State private var page = 1
    @State private var totalPages = 1
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showRecharge = false
    @State private var showWithdraw = false
    @State private var ledgerFilter: WalletLedgerFilter = .all
    @State private var selectedLedgerID: String?
    private let previewSummary: WalletSummaryDTO?
    private let previewTransactions: [WalletTxn]?

    private enum WalletLedgerFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case income = "收入"
        case expense = "支出"
        case escrow = "托管"
        case refund = "退款"
        var id: String { rawValue }
    }

    private var isPreview: Bool { previewSummary != nil && previewTransactions != nil }

    private var selectedLedgerRow: WalletLedgerRow? {
        if isPreview {
            return WalletDesignPreviewFixtures.ledgerRows.first { $0.id == selectedLedgerID }
                ?? WalletDesignPreviewFixtures.ledgerRows.first
        }
        guard let id = selectedLedgerID,
              let item = ledgerItems.first(where: { $0.id == id }) else { return nil }
        return Self.mapLedgerRow(item, service: session.walletService)
    }

    init(
        previewSummary: WalletSummaryDTO? = nil,
        previewTransactions: [WalletTxn]? = nil
    ) {
        self.previewSummary = previewSummary
        self.previewTransactions = previewTransactions
        _summary = State(initialValue: previewSummary)
        _txns = State(initialValue: previewTransactions ?? [])
        _selectedLedgerID = State(initialValue: previewTransactions?.first?.id)
    }

    var body: some View {
        Group {
            if isPreview {
                previewShell
            } else {
                liveShell
            }
        }
        .navigationTitle(isPreview ? "钱包与托管" : "钱包")
        .task { await load(reset: true) }
        .sheet(isPresented: $showRecharge) {
            WalletAmountSheet(
                title: "充值点数",
                subtitle: "内测环境使用平台点数（1 点 = 1 元）。到账后可在流水中查看。",
                confirmTitle: "确认充值"
            ) { amount in
                Task { await recharge(amount) }
            }
            .frame(minWidth: 360, minHeight: 220)
        }
        .sheet(isPresented: $showWithdraw) {
            WalletAmountSheet(
                title: "提现点数",
                subtitle: "内测环境将从可用余额扣减对应点数。",
                confirmTitle: "确认提现"
            ) { amount in
                Task { await withdraw(amount) }
            }
            .frame(minWidth: 360, minHeight: 220)
        }
    }

    private var liveShell: some View {
        HStack(spacing: 0) {
            ScrollView {
                DocumentShell(maxWidth: 1040) {
                    VStack(alignment: .leading, spacing: AppTheme.space24) {
                        Text("1 点 = 1 元。发布需求时托管最低保障；预付仅扣 5% 服务费，验收时结算余款。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let loadError {
                            Text(loadError).foregroundStyle(AppTheme.error)
                        }

                        summaryRow
                        ledgerSection
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let selectedLedgerRow {
                Divider()
                WalletTransactionDetailDrawer(
                    row: selectedLedgerRow,
                    onClose: { selectedLedgerID = nil }
                )
                .frame(width: 320)
            }
        }
    }

    private var previewShell: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.space24) {
                    summaryRow

                    ledgerFilterBar

                    ledgerTable

                    HStack {
                        Text("共 42 条")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("1  2  3  4  5 …")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("10 条 / 页")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(AppTheme.space24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.documentBackground)

            if selectedLedgerID != nil {
                Divider()
                WalletTransactionDetailDrawer(
                    row: WalletDesignPreviewFixtures.ledgerRows.first { $0.id == selectedLedgerID }
                        ?? WalletDesignPreviewFixtures.ledgerRows[0],
                    onClose: { selectedLedgerID = nil }
                )
                .frame(width: 320)
            }
        }
        .background(AppTheme.groupedBackground)
    }

    private var ledgerFilterBar: some View {
        HStack {
            NWFilterPills(items: WalletLedgerFilter.allCases, selection: $ledgerFilter) { $0.rawValue }
            Spacer()
            Text("2024-05-01 ~ 2024-05-31")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.fill.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var ledgerTable: some View {
        VStack(spacing: 0) {
            HStack {
                tableHeader("日期", width: 90)
                tableHeader("类型", width: 56)
                tableHeader("业务对象", flex: true)
                tableHeader("金额(点)", width: 72)
                tableHeader("余额(点)", width: 72)
                tableHeader("状态", width: 56)
                tableHeader("交易 ID", width: 100)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider()

            ForEach(WalletDesignPreviewFixtures.ledgerRows) { row in
                let isSelected = selectedLedgerID == row.id
                Button {
                    selectedLedgerID = row.id
                } label: {
                    HStack(spacing: 8) {
                        tableCell(row.date, width: 90)
                        Image(systemName: row.symbol)
                            .foregroundStyle(row.amountColor)
                            .frame(width: 56)
                        tableCell(row.businessObject, flex: true, alignment: .leading)
                        Text(row.amountText)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(row.amountColor)
                            .frame(width: 72, alignment: .trailing)
                        tableCell(row.balanceText, width: 72, alignment: .trailing)
                        NWStatusChip(text: row.status, tint: row.statusTint)
                            .frame(width: 56)
                        tableCell(row.txnID, width: 100, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .nwSelectionChrome(isSelected: isSelected, cornerRadius: 0)
                Divider()
            }
        }
        .ninewoodCard()
    }

    private func tableHeader(_ title: String, width: CGFloat? = nil, flex: Bool = false) -> some View {
        Group {
            if flex {
                Text(title).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(title).frame(width: width ?? 60, alignment: .leading)
            }
        }
    }

    private func tableCell(
        _ text: String,
        width: CGFloat? = nil,
        flex: Bool = false,
        alignment: Alignment = .leading
    ) -> some View {
        Group {
            if flex {
                Text(text).font(.caption).lineLimit(1).frame(maxWidth: .infinity, alignment: alignment)
            } else {
                Text(text).font(.caption).lineLimit(1).frame(width: width ?? 60, alignment: alignment)
            }
        }
    }

    private var summaryRow: some View {
        HStack(alignment: .top, spacing: AppTheme.space16) {
            walletSummaryCard(
                title: "可用余额",
                value: (summary?.balance.value ?? 0).pointsText,
                detail: "可用于支付服务费用、发起任务等。",
                tint: AppTheme.primary
            )
            walletSummaryCard(
                title: "托管中",
                value: (summary?.held.value ?? 0).pointsText,
                detail: "在保障服务完成前，资金将托管于平台。",
                tint: AppTheme.openStatus
            )
            VStack(alignment: .leading, spacing: AppTheme.space12) {
                Text("在线充值 / 提现")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("充值") { showRecharge = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(isPreview)
                    Button("提现") { showWithdraw = true }
                        .buttonStyle(.bordered)
                        .disabled(isPreview)
                }
                .frame(maxWidth: .infinity)
                Text("当前为内测点数账户。正式支付通道上线前，充值/提现仅变动账户点数。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(AppTheme.space16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ninewoodCard()
        }
    }

    private func walletSummaryCard(
        title: String,
        value: String,
        detail: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.space12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if isLoading && summary == nil {
                ProgressView()
            } else {
                Text(value)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(AppTheme.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninewoodCard()
    }

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("交易流水").font(.headline)
                Spacer()
                Text("本月收入 \((summary?.monthlyIncome?.value ?? 0).pointsText)")
                    .foregroundStyle(AppTheme.openStatus)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("支出 \((summary?.monthlyExpense?.value ?? 0).pointsText)")
                    .foregroundStyle(AppTheme.error)
                Button {
                    Task { await load(reset: true) }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .font(.caption)
            .padding(AppTheme.space16)

            Divider()

            if txns.isEmpty && !isLoading {
                NWEmptyState(title: "暂无流水", systemImage: "list.bullet.rectangle", message: "托管与结算记录会出现在这里")
            } else {
                ForEach(txns) { txn in
                    Button {
                        selectedLedgerID = txn.id
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: txn.symbol)
                                .foregroundStyle(txn.isIncome ? AppTheme.openStatus : AppTheme.primary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(txn.title).font(.body.weight(.semibold))
                                Text(txn.timeText).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(txn.isIncome ? "+" : "-")\(txn.amount.pointsText)")
                                .font(.body.monospacedDigit().weight(.semibold))
                                .foregroundStyle(txn.isIncome ? AppTheme.openStatus : AppTheme.onSurface)
                        }
                        .padding(.horizontal, AppTheme.space16)
                        .padding(.vertical, AppTheme.space12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .nwSelectionChrome(isSelected: selectedLedgerID == txn.id, cornerRadius: 0)
                    Divider().padding(.leading, 56)
                }
                if page < totalPages {
                    Button("加载更多") {
                        Task { await load(reset: false) }
                    }
                    .disabled(isLoading)
                    .padding(AppTheme.space16)
                }
            }
        }
        .ninewoodCard()
    }

    private func load(reset: Bool) async {
        if let previewSummary, let previewTransactions {
            summary = previewSummary
            txns = previewTransactions
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            if reset {
                page = 1
                summary = try await session.walletService.summary()
            }
            let next = reset ? 1 : page + 1
            let ledger = try await session.walletService.ledger(page: next)
            let mapped = session.walletService.mapTransactions(ledger)
            if reset {
                txns = mapped
                ledgerItems = ledger.items
            } else {
                txns.append(contentsOf: mapped)
                ledgerItems.append(contentsOf: ledger.items)
            }
            page = ledger.page
            totalPages = ledger.totalPages
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func recharge(_ amount: Decimal) async {
        do {
            summary = try await session.walletService.recharge(amount: amount)
            showRecharge = false
            await load(reset: true)
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func withdraw(_ amount: Decimal) async {
        do {
            summary = try await session.walletService.withdraw(amount: amount)
            showWithdraw = false
            await load(reset: true)
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    static func mapLedgerRow(_ item: WalletLedgerItemDTO, service: WalletService) -> WalletLedgerRow {
        let amount = item.amount.value
        let isIncome = amount >= 0 || item.type.uppercased() == "CREDIT" || item.type.uppercased() == "RELEASE"
        let typeLabel = WalletService.ledgerTypeLabel(for: item.type, referenceType: item.referenceType)
        let date = APIDate.parse(item.createdAt)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.locale = Locale(identifier: "zh_CN")
        dateTimeFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let amountNumber = abs(amount).pointsText.replacingOccurrences(of: " 点", with: "")
        let balanceNumber = item.balanceAfter.map {
            $0.value.pointsText.replacingOccurrences(of: " 点", with: "")
        } ?? "—"
        return WalletLedgerRow(
            id: item.id,
            date: date.map { dateFormatter.string(from: $0) } ?? APIDate.relativeOrTime(item.createdAt),
            dateTime: date.map { dateTimeFormatter.string(from: $0) } ?? item.createdAt,
            typeLabel: typeLabel,
            businessObject: item.memo ?? item.referenceType ?? item.type,
            amountText: "\(isIncome ? "+" : "-")\(amountNumber)",
            balanceText: balanceNumber,
            status: "已完成",
            statusTint: AppTheme.openStatus,
            txnID: String(item.id.prefix(12)),
            orderID: item.referenceId ?? "—",
            symbol: service.symbol(for: item.type),
            amountColor: isIncome ? AppTheme.openStatus : AppTheme.error
        )
    }
}

private struct WalletAmountSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let subtitle: String
    let confirmTitle: String
    var onConfirm: (Decimal) -> Void

    @State private var amountText = ""

    private var amount: Decimal? {
        Decimal(string: amountText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title3.bold())
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("金额（点）", text: $amountText)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button(confirmTitle) {
                    if let amount, amount > 0 {
                        onConfirm(amount)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(amount == nil || (amount ?? 0) <= 0)
            }
        }
        .padding(24)
    }
}

private struct WalletTransactionDetailDrawer: View {
    let row: WalletLedgerRow
    var onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("交易详情").font(.headline)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                detailSection("基础信息") {
                    detailRow("订单 ID", row.orderID, link: true)
                    detailRow("交易类型", row.typeLabel)
                    HStack {
                        Text("状态").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        NWStatusChip(text: row.status, tint: row.statusTint)
                    }
                    detailRow("交易时间", row.dateTime)
                    detailRow("交易 ID", row.txnID, copy: true)
                }

                detailSection("金额") {
                    detailRow("变动金额", row.amountText)
                    detailRow("余额", row.balanceText)
                    detailRow("业务对象", row.businessObject)
                }

                Text("以上信息由系统自动记录。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
        }
        .background(AppTheme.surface)
    }

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceLow, in: RoundedRectangle(cornerRadius: 8))
    }

    private func detailRow(_ label: String, _ value: String, link: Bool = false, copy: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            if link {
                Text(value)
                    .font(.caption)
                    .foregroundStyle(AppTheme.primary)
            } else {
                Text(value)
                    .font(.caption)
                    .textSelection(.enabled)
            }
            Spacer()
            if copy {
                Image(systemName: "doc.on.doc")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct WalletLedgerRow: Identifiable {
    let id: String
    let date: String
    let dateTime: String
    let typeLabel: String
    let businessObject: String
    let amountText: String
    let balanceText: String
    let status: String
    let statusTint: Color
    let txnID: String
    let orderID: String
    let symbol: String
    let amountColor: Color
}

enum WalletDesignPreviewFixtures {
    static let summary = WalletSummaryDTO(
        balance: FlexibleDecimal(8_640),
        held: FlexibleDecimal(1_200),
        monthlyIncome: FlexibleDecimal(3_460),
        monthlyExpense: FlexibleDecimal(1_920)
    )
    static let transactions: [WalletTxn] = [
        WalletTxn(id: "preview-ledger-1", title: "托管 · 品牌视觉设计交付", timeText: "2024-05-22", amount: 1_200, isIncome: false, symbol: "lock.shield"),
        WalletTxn(id: "preview-ledger-2", title: "结算 · 用户访谈记录整理", timeText: "2024-05-21", amount: 600, isIncome: true, symbol: "checkmark.circle"),
        WalletTxn(id: "preview-ledger-3", title: "支出 · 平台服务费", timeText: "2024-05-20", amount: 120, isIncome: false, symbol: "arrow.up.circle"),
        WalletTxn(id: "preview-ledger-4", title: "退款 · 文档排版优化", timeText: "2024-05-18", amount: 320, isIncome: true, symbol: "arrow.uturn.backward.circle")
    ]

    static let ledgerRows: [WalletLedgerRow] = [
        WalletLedgerRow(
            id: "preview-ledger-1",
            date: "2024-05-22",
            dateTime: "2024-05-22 14:32:08",
            typeLabel: "托管",
            businessObject: "订单 NW202505220001",
            amountText: "-1,200",
            balanceText: "8,640",
            status: "已托管",
            statusTint: AppTheme.openStatus,
            txnID: "TXN-240522-001",
            orderID: "NW202505220001",
            symbol: "lock.shield",
            amountColor: AppTheme.error
        ),
        WalletLedgerRow(
            id: "preview-ledger-2",
            date: "2024-05-21",
            dateTime: "2024-05-21 18:05:00",
            typeLabel: "结算",
            businessObject: "用户访谈记录整理",
            amountText: "+600",
            balanceText: "9,840",
            status: "已完成",
            statusTint: AppTheme.openStatus,
            txnID: "TXN-240521-014",
            orderID: "NW202505210008",
            symbol: "checkmark.circle",
            amountColor: AppTheme.openStatus
        ),
        WalletLedgerRow(
            id: "preview-ledger-3",
            date: "2024-05-20",
            dateTime: "2024-05-20 11:20:00",
            typeLabel: "支出",
            businessObject: "平台服务费",
            amountText: "-120",
            balanceText: "9,240",
            status: "已完成",
            statusTint: AppTheme.openStatus,
            txnID: "TXN-240520-003",
            orderID: "NW202505200004",
            symbol: "arrow.up.circle",
            amountColor: AppTheme.error
        )
    ]
}
