import Foundation
import XCTest
@testable import NinewoodPublishDomain

final class DemandDraftTests: XCTestCase {
    func testBuildsOnlineCommandAndNormalizesInput() throws {
        var draft = DemandDraft()
        draft.title = "  macOS 应用体验测试  "
        draft.expectedOutcome = "\n记录三个交互问题\n"
        draft.minimumPriceText = "1,200.50"
        draft.expectedPriceText = "1500"
        draft.selectedTags = [" UI设计 ", "App开发"]
        draft.allowsNearbyDiscovery = false
        draft.selectedRegionID = 110100

        let command = try draft.publishCommand()

        XCTAssertEqual(command.title, "macOS 应用体验测试")
        XCTAssertEqual(command.expectedOutcome, "记录三个交互问题")
        XCTAssertEqual(command.minimumPrice, Decimal(string: "1200.50"))
        XCTAssertEqual(command.expectedPrice, Decimal(1500))
        XCTAssertEqual(command.tags, ["App开发", "UI设计"])
        XCTAssertEqual(command.category, "App开发")
        XCTAssertEqual(command.serviceType, "ONLINE")
        XCTAssertNil(command.regionID)
    }

    func testRequiresRegionForOfflineDemand() {
        var draft = validDraft()
        draft.allowsNearbyDiscovery = true
        draft.selectedRegionID = nil

        XCTAssertThrowsError(try draft.publishCommand()) { error in
            XCTAssertEqual(error as? DemandDraftValidationError, .missingRegion)
        }
        XCTAssertFalse(draft.hasRequiredContent)
        XCTAssertFalse(draft.canSubmit)
    }

    func testRejectsInvalidMinimumPrice() {
        for value in ["", "0", "-1", "abc"] {
            var draft = validDraft()
            draft.minimumPriceText = value

            XCTAssertThrowsError(try draft.publishCommand()) { error in
                XCTAssertEqual(error as? DemandDraftValidationError, .invalidMinimumPrice)
            }
        }
    }

    func testRejectsInvalidExpectedPrice() {
        var draft = validDraft()
        draft.expectedPriceText = "0"

        XCTAssertThrowsError(try draft.publishCommand()) { error in
            XCTAssertEqual(error as? DemandDraftValidationError, .invalidExpectedPrice)
        }
    }

    func testResetPublishedContentKeepsPreferences() {
        var draft = validDraft()
        draft.selectedTags = ["UI设计"]
        draft.selectedRegionID = 110100
        draft.certifiedProvidersOnly = true
        draft.timeLimitMinutes = 1_440

        draft.resetPublishedContent()

        XCTAssertTrue(draft.title.isEmpty)
        XCTAssertTrue(draft.expectedOutcome.isEmpty)
        XCTAssertTrue(draft.selectedTags.isEmpty)
        XCTAssertNil(draft.selectedRegionID)
        XCTAssertTrue(draft.certifiedProvidersOnly)
        XCTAssertEqual(draft.timeLimitMinutes, 1_440)
        XCTAssertEqual(draft.minimumPriceText, "200")
    }

    func testClampsApplicantLimit() throws {
        var draft = validDraft()
        draft.applicantLimit = 80
        XCTAssertEqual(try draft.publishCommand().maximumApplicants, 50)

        draft.applicantLimit = 0
        XCTAssertEqual(try draft.publishCommand().maximumApplicants, 1)
    }

    private func validDraft() -> DemandDraft {
        var draft = DemandDraft()
        draft.title = "测试需求"
        draft.expectedOutcome = "得到清晰的体验反馈"
        draft.allowsNearbyDiscovery = false
        return draft
    }
}
