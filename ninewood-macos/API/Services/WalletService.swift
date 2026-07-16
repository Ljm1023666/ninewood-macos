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

    func mapTransactions(_ page: WalletLedgerPageDTO) -> [WalletTxn] {
        page.items.map { item in
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
    }

    private func symbol(for type: String) -> String {
        switch type.uppercased() {
        case "HOLD": "lock.fill"
        case "RELEASE": "lock.open.fill"
        case "CREDIT": "arrow.down.circle.fill"
        case "DEBIT": "arrow.up.circle.fill"
        default: "yensign.circle"
        }
    }
}
