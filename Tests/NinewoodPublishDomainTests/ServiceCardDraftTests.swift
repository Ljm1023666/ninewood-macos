import Foundation
import XCTest
@testable import NinewoodPublishDomain

final class ServiceCardDraftTests: XCTestCase {
    func testRequiresTitleDescriptionCategory() throws {
        var draft = ServiceCardDraft()
        XCTAssertThrowsError(try draft.publishCommand()) { error in
            XCTAssertEqual(error as? ServiceCardDraftValidationError, .missingTitle)
        }
        draft.title = "上门清洗"
        XCTAssertThrowsError(try draft.publishCommand()) { error in
            XCTAssertEqual(error as? ServiceCardDraftValidationError, .missingDescription)
        }
        draft.description = "提供周末上门家电清洗"
        draft.category = ""
        XCTAssertThrowsError(try draft.publishCommand()) { error in
            XCTAssertEqual(error as? ServiceCardDraftValidationError, .missingCategory)
        }
        draft.category = "家政"
        let command = try draft.publishCommand()
        XCTAssertEqual(command.title, "上门清洗")
        XCTAssertEqual(command.category, "家政")
    }

    func testRejectsInvertedPriceRange() {
        var draft = ServiceCardDraft()
        draft.title = "设计咨询"
        draft.description = "品牌视觉咨询"
        draft.category = "设计"
        draft.priceMinText = "500"
        draft.priceMaxText = "100"
        XCTAssertThrowsError(try draft.publishCommand()) { error in
            XCTAssertEqual(error as? ServiceCardDraftValidationError, .priceRangeInvalid)
        }
    }

    func testPacksClaimsAndUnitIntoTags() throws {
        var draft = ServiceCardDraft()
        draft.title = "陪诊"
        draft.description = "三甲医院陪诊"
        draft.category = "陪诊"
        draft.priceUnit = "次"
        draft.claims = ["持证上岗", "同城 2 小时响应"]
        let command = try draft.publishCommand()
        XCTAssertTrue(command.tags.contains("持证上岗"))
        XCTAssertTrue(command.tags.contains(where: { $0.hasPrefix("单位:") }))
    }
}
