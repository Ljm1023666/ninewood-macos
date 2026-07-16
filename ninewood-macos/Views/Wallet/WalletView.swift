import SwiftUI

struct WalletView: View {
    @Environment(AppSession.self) private var session
    @State private var summary: WalletSummaryDTO?
    @State private var txns: [WalletTxn] = []
    @State private var page = 1
    @State private var totalPages = 1
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var topupHint = false

    var body: some View {
        DocumentShell(maxWidth: AppTheme.documentWideMaxWidth) {
            VStack(alignment: .leading, spacing: AppTheme.space24) {
                Text("1 点 = 1 元。发布需求时托管最低保障；预付仅扣 5% 服务费，验收时结算余款。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let loadError {
                    Text(loadError).foregroundStyle(AppTheme.error)
                }

                balanceHero
                statsRow
                actionsRow
                ledgerSection
            }
        }
        .navigationTitle("钱包")
        .task { await load(reset: true) }
        .alert("充值", isPresented: $topupHint) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("开发期暂不支持在线充值，请联系管理员调账。")
        }
    }

    private var balanceHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("可用余额").font(.caption).foregroundStyle(.secondary)
            if isLoading && summary == nil {
                ProgressView()
            } else {
                Text((summary?.balance.value ?? 0).pointsText)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primary)
            }
            Text("托管中 \((summary?.held.value ?? 0).pointsText)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .ninewoodCard()
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard("本月入账", (summary?.monthlyIncome?.value ?? 0).pointsText)
            statCard("本月支出", (summary?.monthlyExpense?.value ?? 0).pointsText)
        }
    }

    private func statCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .ninewoodCard()
    }

    private var actionsRow: some View {
        HStack(spacing: 12) {
            Button("刷新") { Task { await load(reset: true) } }
                .buttonStyle(.bordered)
            Button("充值") { topupHint = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("流水").font(.headline)
            if txns.isEmpty && !isLoading {
                NWEmptyState(title: "暂无流水", systemImage: "list.bullet.rectangle", message: "托管与结算记录会出现在这里")
            } else {
                ForEach(txns) { txn in
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
                    .padding(.vertical, 8)
                    Divider()
                }
                if page < totalPages {
                    Button("加载更多") {
                        Task { await load(reset: false) }
                    }
                    .disabled(isLoading)
                }
            }
        }
        .padding(16)
        .ninewoodCard()
    }

    private func load(reset: Bool) async {
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
            } else {
                txns.append(contentsOf: mapped)
            }
            page = ledger.page
            totalPages = ledger.totalPages
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
