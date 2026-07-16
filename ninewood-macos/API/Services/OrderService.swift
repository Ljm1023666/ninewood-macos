import Foundation

@MainActor
final class OrderService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func list(role: String? = nil, page: Int = 1) async throws -> [Order] {
        var query = [URLQueryItem(name: "page", value: String(page))]
        if let role { query.append(URLQueryItem(name: "role", value: role)) }
        let result: OrderListResult = try await client.get("/orders", query: query)
        return result.orders.map(OrderMapper.map)
    }

    func get(id: String) async throws -> Order {
        let dto: OrderDTO = try await client.get("/orders/\(id)")
        return OrderMapper.map(dto)
    }

    @discardableResult
    func prepay(id: String) async throws -> OrderPrepayResultDTO {
        try await client.post("/orders/\(id)/prepay")
    }

    func complete(id: String) async throws {
        struct OK: Decodable { let message: String? }
        let _: OK = try await client.post("/orders/\(id)/complete")
    }

    func confirm(id: String) async throws -> OrderConfirmResultDTO {
        try await client.post("/orders/\(id)/confirm")
    }

    func dispute(id: String, reason: String) async throws {
        struct Body: Encodable {
            let reason: String
            let description: String
        }
        struct OK: Decodable { let message: String? }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let _: OK = try await client.post(
            "/orders/\(id)/dispute",
            body: Body(reason: trimmed, description: trimmed)
        )
    }

    func cancel(id: String) async throws {
        struct OK: Decodable { let message: String? }
        let _: OK = try await client.post("/orders/\(id)/cancel")
    }

    func partial(id: String, newPrice: Decimal, description: String) async throws -> OrderPartialResultDTO {
        struct Body: Encodable {
            let newPrice: Double
            let description: String
        }
        return try await client.post(
            "/orders/\(id)/partial",
            body: Body(
                newPrice: NSDecimalNumber(decimal: newPrice).doubleValue,
                description: description
            )
        )
    }
}

struct OrderPrepayResultDTO: Decodable {
    let message: String?
    let amount: FlexibleDecimal?
    let serviceFee: FlexibleDecimal?
}

struct OrderConfirmResultDTO: Decodable {
    let message: String?
    let breakdown: SettlementBreakdownDTO?
}

struct OrderPartialResultDTO: Decodable {
    let message: String?
    let originalOrderId: String?
    let settledPrice: FlexibleDecimal?
    let remainingDemandId: String?
}

struct SettlementBreakdownDTO: Decodable {
    let minPrice: FlexibleDecimal?
    let finalPrice: FlexibleDecimal?
    let serviceFee: FlexibleDecimal?
    let demanderPaid: FlexibleDecimal?
    let providerReceived: FlexibleDecimal?
    let platformRevenue: FlexibleDecimal?
    let depositReturned: FlexibleDecimal?
}

enum OrderMapper {
    static func map(_ dto: OrderDTO) -> Order {
        let deal = dto.agreedPrice?.value ?? dto.demand?.minPrice?.value ?? 0
        let escrow = dto.demand?.minPrice?.value ?? deal
        let remaining = max(0, deal - escrow)
        let fee = (deal * Decimal(string: "0.05")!).rounded(scale: 2)

        let demandStub = Demand(
            id: dto.demand?.id ?? dto.demandId ?? dto.id,
            title: dto.demand?.title ?? "订单需求",
            expectedOutcome: dto.demand?.description ?? "",
            minPrice: escrow,
            expectedPrice: deal,
            distanceText: "—",
            countdownText: "—",
            applicantCount: 0,
            applicantLimit: 10,
            tags: dto.demand?.category.map { [$0] } ?? [],
            state: .normal,
            publisher: mapUser(dto.requester),
            deadlineText: APIDate.relativeOrTime(dto.createdAt),
            isCertifiedOnly: false,
            allowNearby: true
        )

        return Order(
            id: dto.id,
            demand: demandStub,
            provider: mapUser(dto.provider),
            requesterId: dto.requester?.id,
            providerId: dto.provider?.id,
            stage: stage(from: dto.status),
            rawStatus: dto.status,
            paidAt: dto.paidAt,
            completedAt: dto.completedAt,
            submittedAtText: APIDate.relativeOrTime(dto.createdAt),
            dealAmount: deal,
            escrowAmount: escrow,
            remainingPay: remaining,
            serviceFee: fee,
            amountHint: dto.status
        )
    }

    private static func mapUser(_ user: SoftUserDTO?) -> AppUser {
        AppUser.from(user)
    }

    private static func stage(from status: String) -> Order.Stage {
        switch status.uppercased() {
        case "PENDING": .accepted
        case "IN_PROGRESS": .inProgress
        case "WAITING_REVIEW": .waitingReview
        case "COMPLETED": .completed
        case "DISPUTED": .disputed
        case "CANCELLED", "REFUNDED": .completed
        default: .inProgress
        }
    }
}

private extension Decimal {
    func rounded(scale: Int) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}
