import Foundation
import XCTest
@testable import NinewoodPublishDomain

/// 发布工作区纯逻辑冒烟（对齐 Windows demand-publish / missing queue 行为）。
final class PublishWorkspaceRulesSmokeTests: XCTestCase {
    func testDemandDraftStillPublishesWithEscrowFields() throws {
        var draft = DemandDraft()
        draft.title = "浦东修空调"
        draft.expectedOutcome = "当天上门修好制冷"
        draft.minimumPriceText = "200"
        draft.expectedPriceText = "350"
        draft.allowsNearbyDiscovery = true
        draft.selectedRegionID = 310115
        draft.selectedTags = ["家政/维修"]
        let command = try draft.publishCommand()
        XCTAssertEqual(command.serviceType, "OFFLINE")
        XCTAssertEqual(command.regionID, 310115)
        XCTAssertEqual(command.category, "家政/维修")
    }

    func testServiceCardDraftReadyGate() {
        var draft = ServiceCardDraft()
        XCTAssertFalse(draft.hasRequiredContent)
        draft.title = "周末家电清洗"
        draft.description = "同城上门，2小时响应"
        draft.category = "日常服务"
        XCTAssertTrue(draft.hasRequiredContent)
        XCTAssertTrue(draft.canSubmit)
    }
}
