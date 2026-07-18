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

    func payBreakdown(id: String) async throws -> OrderPayBreakdownDTO {
        try await client.get("/orders/\(id)/pay-breakdown")
    }

    func uploadEvidence(fileData: Data, fileName: String, mimeType: String = "image/jpeg") async throws -> EvidenceUploadResultDTO {
        try await client.postMultipart(
            "/orders/uploads/evidence",
            fields: [:],
            files: [
                MultipartFile(
                    fieldName: "file",
                    fileName: fileName,
                    mimeType: mimeType,
                    data: fileData
                )
            ]
        )
    }

    func dispute(id: String, reason: String, evidenceUrls: [String] = []) async throws {
        struct Body: Encodable {
            let reason: String
            let description: String
            let evidenceUrls: [String]
        }
        struct OK: Decodable { let message: String? }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let _: OK = try await client.post(
            "/orders/\(id)/dispute",
            body: Body(
                reason: trimmed,
                description: trimmed,
                evidenceUrls: evidenceUrls
            )
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

enum OrderMapper {
    static func map(_ dto: OrderDTO) -> Order {
        let deal = dto.agreedPrice?.value ?? dto.demand?.minPrice?.value ?? 0
        let minPrice = dto.demand?.minPrice?.value ?? deal
        // 托管金额只信服务端 deposit / escrow*；缺失时列表显示 0 并标注，禁止用 minPrice 冒充应付。
        let depositFromDemand = dto.demand?.deposit?.value
        let escrow =
            dto.escrowAmount?.value
            ?? dto.escrowRequired?.value
            ?? dto.depositRequired?.value
            ?? depositFromDemand
        let remaining =
            dto.remainingPay?.value
            ?? (escrow.map { max(0, deal - $0) })
        let fee = dto.serviceFee?.value
        let amountsFromServer = escrow != nil

        let demandStub = Demand(
            id: dto.demand?.id ?? dto.demandId ?? dto.id,
            title: dto.demand?.title ?? "订单需求",
            expectedOutcome: dto.demand?.description ?? "",
            minPrice: minPrice,
            expectedPrice: deal,
            deposit: depositFromDemand ?? escrow,
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

        let hint: String
        if let version = dto.ruleVersion, !version.isEmpty {
            hint = "规则 \(version)"
        } else if amountsFromServer {
            hint = dto.status
        } else {
            hint = "金额以付款预览为准"
        }

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
            escrowAmount: escrow ?? 0,
            remainingPay: remaining ?? 0,
            serviceFee: fee ?? 0,
            amountHint: hint,
            amountsFromServer: amountsFromServer
        )
    }

    private static func mapUser(_ user: SoftUserDTO?) -> AppUser {
        AppUser.from(user)
    }

    static func stage(from status: String) -> Order.Stage {
        switch status.uppercased() {
        case "PENDING": .accepted
        case "IN_PROGRESS": .inProgress
        case "WAITING_REVIEW": .waitingReview
        case "COMPLETED": .completed
        case "DISPUTED": .disputed
        case "CANCELLED", "REFUNDED": .cancelled
        default: .inProgress
        }
    }
}
