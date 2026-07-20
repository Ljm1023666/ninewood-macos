import Foundation

/// 服务卡独立草稿（与需求卡分离的数据模型与校验）。
struct ServiceCardDraft: Equatable, Sendable {
    var title = ""
    var summary = ""
    var description = ""
    var category = "日常服务"
    /// ONLINE / OFFLINE / HYBRID
    var serviceType = "ONLINE"
    /// REMOTE / ONSITE / HYBRID
    var deliveryMode = "REMOTE"
    var priceMinText = ""
    var priceMaxText = ""
    var priceUnit = "次"
    /// 能力声明（写入 tags）
    var claims: [String] = []

    var hasRequiredContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSubmit: Bool {
        (try? publishCommand()) != nil
    }

    mutating func applyPrefill(
        title: String? = nil,
        summary: String? = nil,
        description: String? = nil,
        category: String? = nil,
        serviceType: String? = nil,
        deliveryMode: String? = nil,
        priceMin: String? = nil,
        priceMax: String? = nil,
        priceUnit: String? = nil,
        claims: [String]? = nil
    ) {
        if let title, self.title.isEmpty { self.title = title }
        if let summary, self.summary.isEmpty { self.summary = summary }
        if let description, self.description.isEmpty { self.description = description }
        if let category, !category.isEmpty { self.category = category }
        if let serviceType, !serviceType.isEmpty { self.serviceType = serviceType }
        if let deliveryMode, !deliveryMode.isEmpty { self.deliveryMode = deliveryMode }
        if let priceMin, self.priceMinText.isEmpty { self.priceMinText = priceMin }
        if let priceMax, self.priceMaxText.isEmpty { self.priceMaxText = priceMax }
        if let priceUnit, !priceUnit.isEmpty { self.priceUnit = priceUnit }
        if let claims, self.claims.isEmpty {
            self.claims = claims.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
    }

    mutating func resetPublishedContent() {
        title = ""
        summary = ""
        description = ""
        claims = []
        priceMinText = ""
        priceMaxText = ""
    }

    func publishCommand() throws -> ServiceCardPublishCommand {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { throw ServiceCardDraftValidationError.missingTitle }

        let normalizedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDescription.isEmpty else { throw ServiceCardDraftValidationError.missingDescription }

        let normalizedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCategory.isEmpty else { throw ServiceCardDraftValidationError.missingCategory }

        let priceMin = try Self.optionalPositive(from: priceMinText, error: .invalidPriceMin)
        let priceMax = try Self.optionalPositive(from: priceMaxText, error: .invalidPriceMax)
        if let priceMin, let priceMax, priceMax < priceMin {
            throw ServiceCardDraftValidationError.priceRangeInvalid
        }

        var tags = claims
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let unit = priceUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        if !unit.isEmpty, !tags.contains(where: { $0.hasPrefix("单位:") }) {
            tags.append("单位:\(unit)")
        }

        let summaryText = summary.trimmingCharacters(in: .whitespacesAndNewlines)

        return ServiceCardPublishCommand(
            title: normalizedTitle,
            summary: summaryText.isEmpty ? nil : summaryText,
            description: normalizedDescription,
            category: normalizedCategory,
            serviceType: serviceType,
            tags: tags,
            priceMin: priceMin,
            priceMax: priceMax,
            deliveryMode: deliveryMode
        )
    }

    private static func optionalPositive(
        from text: String,
        error: ServiceCardDraftValidationError
    ) throws -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        guard let value = Decimal(string: trimmed.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX")),
              value > 0
        else {
            throw error
        }
        return value
    }
}

struct ServiceCardPublishCommand: Equatable, Sendable {
    let title: String
    let summary: String?
    let description: String
    let category: String
    let serviceType: String
    let tags: [String]
    let priceMin: Decimal?
    let priceMax: Decimal?
    let deliveryMode: String
}

enum ServiceCardDraftValidationError: LocalizedError, Equatable {
    case missingTitle
    case missingDescription
    case missingCategory
    case invalidPriceMin
    case invalidPriceMax
    case priceRangeInvalid

    var errorDescription: String? {
        switch self {
        case .missingTitle: "请填写服务标题"
        case .missingDescription: "请填写服务说明"
        case .missingCategory: "请填写服务类别"
        case .invalidPriceMin: "请填写有效的最低报价"
        case .invalidPriceMax: "请填写有效的最高报价"
        case .priceRangeInvalid: "最高报价不能低于最低报价"
        }
    }
}
