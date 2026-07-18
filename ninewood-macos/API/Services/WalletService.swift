import Foundation

@MainActor
final class WalletService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func summary() async throws -> WalletSummaryDTO {
        try await client.get("/wallet/balance")
    }

    func ledger(page: Int = 1, limit: Int = 20) async throws -> WalletLedgerPageDTO {
        try await client.get(
            "/wallet/ledger",
            query: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
    }

    func recharge(amount: Decimal) async throws -> WalletSummaryDTO {
        struct Body: Encodable { let amount: Double }
        struct Wrap: Decodable {
            let balance: FlexibleDecimal?
            let held: FlexibleDecimal?
            let monthlyIncome: FlexibleDecimal?
            let monthlyExpense: FlexibleDecimal?
        }
        let amountValue = NSDecimalNumber(decimal: amount).doubleValue
        let wrap: Wrap = try await client.post(
            "/wallet/recharge",
            body: Body(amount: amountValue)
        )
        if let balance = wrap.balance {
            return WalletSummaryDTO(
                balance: balance,
                held: wrap.held ?? FlexibleDecimal(0),
                monthlyIncome: wrap.monthlyIncome,
                monthlyExpense: wrap.monthlyExpense
            )
        }
        return try await summary()
    }

    func withdraw(amount: Decimal) async throws -> WalletSummaryDTO {
        struct Body: Encodable { let amount: Double }
        struct Wrap: Decodable {
            let balance: FlexibleDecimal?
            let held: FlexibleDecimal?
            let monthlyIncome: FlexibleDecimal?
            let monthlyExpense: FlexibleDecimal?
        }
        let amountValue = NSDecimalNumber(decimal: amount).doubleValue
        let wrap: Wrap = try await client.post(
            "/wallet/withdraw",
            body: Body(amount: amountValue)
        )
        if let balance = wrap.balance {
            return WalletSummaryDTO(
                balance: balance,
                held: wrap.held ?? FlexibleDecimal(0),
                monthlyIncome: wrap.monthlyIncome,
                monthlyExpense: wrap.monthlyExpense
            )
        }
        return try await summary()
    }

    func mapTransactions(_ page: WalletLedgerPageDTO) -> [WalletTxn] {
        page.items.map(mapTransaction)
    }

    func mapTransaction(_ item: WalletLedgerItemDTO) -> WalletTxn {
        let amount = item.amount.value
        let isIncome = amount >= 0 || item.type == "CREDIT" || item.type == "RELEASE"
        return WalletTxn(
            id: item.id,
            title: item.memo ?? item.type,
            timeText: APIDate.relativeOrTime(item.createdAt),
            amount: abs(amount),
            isIncome: isIncome,
            symbol: symbol(for: item.type)
        )
    }

    static func ledgerTypeLabel(for type: String, referenceType: String?) -> String {
        let ref = (referenceType ?? "").uppercased()
        if ref == "RECHARGE" { return "充值" }
        if ref == "WITHDRAW" { return "提现" }
        switch type.uppercased() {
        case "HOLD": return "托管"
        case "RELEASE": return "结算"
        case "CREDIT": return "收入"
        case "DEBIT": return "支出"
        default: return type
        }
    }

    func symbol(for type: String) -> String {
        switch type.uppercased() {
        case "HOLD": "lock.fill"
        case "RELEASE": "lock.open.fill"
        case "CREDIT": "arrow.down.circle.fill"
        case "DEBIT": "arrow.up.circle.fill"
        default: "yensign.circle"
        }
    }
}
