import Foundation

/// Work 助手 → 专用发布页的草稿交接。最终确认/提交只在页面完成，禁止静默写库。
struct PublishDraftHandoff: Equatable, Sendable {
    enum Kind: String, Sendable {
        case demand
        case service
    }

    var kind: Kind
    var title: String = ""
    var summary: String = ""
    var description: String = ""
    var category: String = ""
    var expectedOutcome: String = ""
    var budgetMin: String = ""
    var budgetMax: String = ""
    var priceUnit: String = ""
    var serviceType: String = ""
    var deliveryMode: String = ""
    var regionHint: String = ""
    var claims: [String] = []
    var source: String = "agent"

    var targetPath: String {
        switch kind {
        case .demand: "/demands/create"
        case .service: "/service-cards/create"
        }
    }
}
