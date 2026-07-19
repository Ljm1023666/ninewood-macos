import XCTest
@testable import NinewoodAPIContracts

final class APIConfigTests: XCTestCase {
    func testAcceptsAbsoluteHTTPSMediaURL() {
        XCTAssertEqual(
            APIConfig.mediaURL("https://cdn.example.com/image.png")?.absoluteString,
            "https://cdn.example.com/image.png"
        )
    }

    func testRejectsInsecureAndNonWebAbsoluteMediaURLs() {
        XCTAssertNil(APIConfig.mediaURL("http://cdn.example.com/image.png"))
        XCTAssertNil(APIConfig.mediaURL("file:///tmp/private.txt"))
        XCTAssertNil(APIConfig.mediaURL("javascript:alert(1)"))
    }

    func testResolvesRelativeMediaPathsAgainstMediaHost() {
        XCTAssertEqual(
            APIConfig.mediaURL("/uploads/image.png")?.absoluteString,
            "https://tothetomorrow.com/uploads/image.png"
        )
        XCTAssertEqual(
            APIConfig.mediaURL("uploads/image.png")?.absoluteString,
            "https://tothetomorrow.com/uploads/image.png"
        )
    }
}
