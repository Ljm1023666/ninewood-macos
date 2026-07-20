import Foundation

enum PublishDraftAIMapper {
    static func apply(_ result: PublishAnalyzeResult, to draft: inout DemandDraft, detailedDescription: inout String) {
        if let title = result.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            draft.title = title
        }
        let outcome = (result.expectedOutcome ?? result.summary)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !outcome.isEmpty {
            draft.expectedOutcome = String(outcome.prefix(80))
            if detailedDescription.isEmpty {
                detailedDescription = outcome
            }
        }
        if let budget = result.budget?.trimmingCharacters(in: .whitespacesAndNewlines), !budget.isEmpty {
            let digits = budget.filter { $0.isNumber || $0 == "." }
            if !digits.isEmpty {
                draft.minimumPriceText = digits
            }
        }
        if let serviceType = result.serviceType?.uppercased() {
            draft.allowsNearbyDiscovery = serviceType != "ONLINE"
        }
        if let regionId = result.regionId {
            draft.selectedRegionID = regionId
        }
        if let category = result.category?.trimmingCharacters(in: .whitespacesAndNewlines), !category.isEmpty {
            draft.selectedTags.insert(category)
        }
        for label in result.effectiveScopeLabels where !label.isEmpty {
            draft.selectedTags.insert(label)
        }
        for keyword in result.suggestedKeywords ?? [] where !keyword.isEmpty {
            draft.selectedTags.insert(keyword)
        }
    }

    static func apply(_ result: PublishAnalyzeResult, to draft: inout ServiceCardDraft) {
        if let title = result.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            draft.title = title
        }
        if let summary = result.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            draft.summary = String(summary.prefix(80))
            if draft.description.isEmpty {
                draft.description = summary
            }
        }
        if let category = result.category?.trimmingCharacters(in: .whitespacesAndNewlines), !category.isEmpty {
            draft.category = category
        }
        if let serviceType = result.serviceType?.uppercased(), !serviceType.isEmpty {
            draft.serviceType = serviceType
            if serviceType == "ONLINE" { draft.deliveryMode = "REMOTE" }
            else if serviceType == "OFFLINE" { draft.deliveryMode = "ONSITE" }
            else { draft.deliveryMode = "HYBRID" }
        }
        if let budget = result.budget?.trimmingCharacters(in: .whitespacesAndNewlines), !budget.isEmpty {
            let digits = budget.filter { $0.isNumber || $0 == "." }
            if !digits.isEmpty {
                draft.priceMinText = digits
            }
        }
        let keywords = (result.suggestedKeywords ?? []) + result.effectiveScopeLabels
        for keyword in keywords where !keyword.isEmpty && !draft.claims.contains(keyword) {
            draft.claims.append(keyword)
        }
    }
}
