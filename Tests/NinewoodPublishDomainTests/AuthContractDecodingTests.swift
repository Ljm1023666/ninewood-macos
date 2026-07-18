import Foundation
import XCTest
@testable import NinewoodAPIContracts

final class AuthContractDecodingTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testAuthPayloadLoginContract() throws {
        let envelope = Data(
            """
            {
              "code": 200,
              "message": "登录成功",
              "data": {
                "token": "jwt-token",
                "user": {
                  "id": "user-1",
                  "accountNo": 861,
                  "phone": "19900001234",
                  "nickname": "用户_1234",
                  "avatarUrl": null,
                  "coverUrl": null,
                  "demandCardCoverUrl": null,
                  "certificationLevel": "NONE",
                  "creditScore": 60,
                  "completedOrders": 0
                }
              },
              "timestamp": 1784383006511
            }
            """.utf8
        )

        let decoded = try decoder.decode(APIEnvelope<AuthPayloadDTO>.self, from: envelope)
        let payload = try XCTUnwrap(decoded.data)

        XCTAssertEqual(payload.token, "jwt-token")
        XCTAssertEqual(payload.user.id, "user-1")
        XCTAssertEqual(payload.user.phone, "19900001234")
        XCTAssertEqual(payload.user.completedOrders, 0)
    }
}
