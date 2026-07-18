import Foundation

/// 发布需求的纯领域草稿。
///
/// 该类型不依赖 SwiftUI 或网络层，因此金额、位置和必填项规则可以独立测试。
struct DemandDraft: Equatable, Sendable {
    var title = ""
    var expectedOutcome = ""
    var minimumPriceText = "200"
    var expectedPriceText = ""
    var timeLimitMinutes = 180
    var applicantLimit = 10
    var selectedTags: Set<String> = []
    var selectedRegionID: Int?
    var allowsNearbyDiscovery = true
    var certifiedProvidersOnly = false

    var canSubmit: Bool {
        (try? publishCommand()) != nil
    }

    /// 控制提交按钮的基础完整性；金额格式等详细错误在点击后给出明确提示。
    var hasRequiredContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !expectedOutcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!allowsNearbyDiscovery || selectedRegionID != nil)
    }

    var escrowDisclosure: String {
        "发布时需将最低保障 \(minimumPriceText.isEmpty ? "0" : minimumPriceText) 点预付至平台托管"
    }

    mutating func applyInitialContent(title: String, expectedOutcome: String) {
        if self.title.isEmpty, !title.isEmpty {
            self.title = title
        }
        if self.expectedOutcome.isEmpty, !expectedOutcome.isEmpty {
            self.expectedOutcome = expectedOutcome
        }
    }

    /// 嵌入式发布成功后只清除本次内容，保留用户选择的常用发布偏好。
    mutating func resetPublishedContent() {
        title = ""
        expectedOutcome = ""
        selectedTags = []
        selectedRegionID = nil
    }

    func publishCommand() throws -> DemandPublishCommand {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw DemandDraftValidationError.missingTitle
        }

        let normalizedOutcome = expectedOutcome.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedOutcome.isEmpty else {
            throw DemandDraftValidationError.missingExpectedOutcome
        }

        guard let minimumPrice = Self.decimal(from: minimumPriceText), minimumPrice > 0 else {
            throw DemandDraftValidationError.invalidMinimumPrice
        }

        let expectedPrice: Decimal?
        if expectedPriceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            expectedPrice = nil
        } else {
            guard let parsed = Self.decimal(from: expectedPriceText), parsed > 0 else {
                throw DemandDraftValidationError.invalidExpectedPrice
            }
            expectedPrice = parsed
        }

        guard !allowsNearbyDiscovery || selectedRegionID != nil else {
            throw DemandDraftValidationError.missingRegion
        }

        let tags = selectedTags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()

        return DemandPublishCommand(
            title: normalizedTitle,
            expectedOutcome: normalizedOutcome,
            minimumPrice: minimumPrice,
            expectedPrice: expectedPrice,
            category: tags.first ?? "日常服务",
            serviceType: allowsNearbyDiscovery ? "OFFLINE" : "ONLINE",
            maximumApplicants: min(max(applicantLimit, 1), 50),
            certifiedProvidersOnly: certifiedProvidersOnly,
            tags: tags,
            regionID: allowsNearbyDiscovery ? selectedRegionID : nil,
            timeLimitMinutes: timeLimitMinutes
        )
    }

    private static func decimal(from text: String) -> Decimal? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }
}

struct DemandPublishCommand: Equatable, Sendable {
    let title: String
    let expectedOutcome: String
    let minimumPrice: Decimal
    let expectedPrice: Decimal?
    let category: String
    let serviceType: String
    let maximumApplicants: Int
    let certifiedProvidersOnly: Bool
    let tags: [String]
    let regionID: Int?
    let timeLimitMinutes: Int
}

enum DemandDraftValidationError: LocalizedError, Equatable {
    case missingTitle
    case missingExpectedOutcome
    case invalidMinimumPrice
    case invalidExpectedPrice
    case missingRegion

    var errorDescription: String? {
        switch self {
        case .missingTitle:
            "请填写需求标题"
        case .missingExpectedOutcome:
            "请填写期望效果"
        case .invalidMinimumPrice:
            "请填写有效的最低保障金额"
        case .invalidExpectedPrice:
            "请填写有效的预计成交金额"
        case .missingRegion:
            "线下需求请选择服务地区"
        }
    }
}
