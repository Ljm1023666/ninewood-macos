import Foundation

/// 订单领域的数据与命令入口。
@MainActor
final class OrderRepository {
    private let service: OrderService

    init(service: OrderService) {
        self.service = service
    }

    func list(role: String? = nil, page: Int = 1) async throws -> [Order] {
        try await service.list(role: role, page: page)
    }

    func detail(id: String) async throws -> Order {
        try await service.get(id: id)
    }

    func prepay(id: String) async throws -> OrderPrepayResultDTO {
        try await service.prepay(id: id)
    }

    func complete(id: String) async throws {
        try await service.complete(id: id)
    }

    func confirm(id: String) async throws -> OrderConfirmResultDTO {
        try await service.confirm(id: id)
    }

    func payBreakdown(id: String) async throws -> OrderPayBreakdownDTO {
        try await service.payBreakdown(id: id)
    }

    func uploadEvidence(fileData: Data, fileName: String, mimeType: String = "image/jpeg") async throws -> EvidenceUploadResultDTO {
        try await service.uploadEvidence(fileData: fileData, fileName: fileName, mimeType: mimeType)
    }

    func dispute(id: String, reason: String, evidenceUrls: [String] = []) async throws {
        try await service.dispute(id: id, reason: reason, evidenceUrls: evidenceUrls)
    }

    func cancel(id: String) async throws {
        try await service.cancel(id: id)
    }

    func completePartially(
        id: String,
        newPrice: Decimal,
        description: String
    ) async throws -> OrderPartialResultDTO {
        try await service.partial(id: id, newPrice: newPrice, description: description)
    }
}
