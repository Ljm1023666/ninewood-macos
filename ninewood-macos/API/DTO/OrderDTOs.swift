import Foundation

struct OrderListResult: Decodable {
    let orders: [OrderDTO]
    let total: Int
    let page: Int
    let totalPages: Int
}

struct OrderDTO: Decodable {
    let id: String
    let demandId: String?
    let status: String
    let agreedPrice: FlexibleDecimal?
    let paidAt: String?
    let completedAt: String?
    let createdAt: String?
    let provider: SoftUserDTO?
    let requester: SoftUserDTO?
    let demand: OrderDemandDTO?
    /// 服务端资金摘要（列表/详情）；付款确认仍以 pay-breakdown 为准。
    let currency: String?
    let ruleVersion: String?
    let depositRequired: FlexibleDecimal?
    let escrowRequired: FlexibleDecimal?
    let escrowAmount: FlexibleDecimal?
    let serviceFeeRate: Double?
    let serviceFee: FlexibleDecimal?
    let remainingPay: FlexibleDecimal?
    let payableNow: FlexibleDecimal?
}

struct OrderDemandDTO: Decodable {
    let id: String
    let title: String?
    let description: String?
    let minPrice: FlexibleDecimal?
    let deposit: FlexibleDecimal?
    let category: String?
    /// Prisma `DateTime?`，生产返回 ISO 字符串；兼容历史 Int 以免整单失败。
    let timeLimit: FlexibleDateValue?
}

/// `GET /orders/:id/pay-breakdown` 服务端付款预览。
struct OrderPayBreakdownDTO: Decodable {
    let currency: String?
    let ruleVersion: String?
    let minimumPrice: FlexibleDecimal?
    let agreedPrice: FlexibleDecimal?
    let depositRequired: FlexibleDecimal?
    let escrowHeld: FlexibleDecimal?
    let serviceFeeRate: Double?
    let serviceFee: FlexibleDecimal?
    let payableNow: FlexibleDecimal?
    let alreadyPrepaid: Bool?
    let breakdown: SettlementBreakdownDTO?
}

struct EvidenceUploadResultDTO: Decodable {
    let url: String
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
