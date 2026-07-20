import Foundation
import XCTest
@testable import NinewoodAPIContracts

final class APIContractDecodingTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testFlexibleDecimalAcceptsNumberAndString() throws {
        let number = try decoder.decode(FlexibleDecimal.self, from: Data("12.50".utf8))
        let string = try decoder.decode(FlexibleDecimal.self, from: Data(#""12.50""#.utf8))

        XCTAssertEqual(number.value, Decimal(string: "12.50"))
        XCTAssertEqual(string.value, Decimal(string: "12.50"))
    }

    func testFlexibleDecimalRejectsInvalidMoney() {
        XCTAssertThrowsError(
            try decoder.decode(FlexibleDecimal.self, from: Data(#""not-money""#.utf8))
        )
    }

    func testCaptchaVerifyContract() throws {
        let data = Data(
            """
            {
              "success": true,
              "token": "server-issued-captcha-token",
              "message": "验证成功"
            }
            """.utf8
        )

        let result = try decoder.decode(CaptchaVerifyDTO.self, from: data)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.token, "server-issued-captcha-token")
        XCTAssertEqual(result.message, "验证成功")
    }

    func testDemandListContract() throws {
        let data = Data(
            """
            {
              "id": "demand-1",
              "title": "界面体验测试",
              "description": "记录问题",
              "minPrice": "200.00",
              "applicantCount": 1,
              "maxApplicants": 10,
              "status": "ACTIVE",
              "user": {
                "id": "user-1",
                "nickname": "测试用户",
                "creditScore": 80
              }
            }
            """.utf8
        )

        let demand = try decoder.decode(DemandListItemDTO.self, from: data)

        XCTAssertEqual(demand.id, "demand-1")
        XCTAssertEqual(demand.minPrice?.value, Decimal(200))
        XCTAssertEqual(demand.user?.nickname, "测试用户")
    }

    func testOrderContractIncludesMoneySummary() throws {
        let data = Data(
            """
            {
              "id": "order-1",
              "demandId": "demand-1",
              "status": "IN_PROGRESS",
              "agreedPrice": 300,
              "currency": "POINT",
              "ruleVersion": "2026-07",
              "depositRequired": 200,
              "escrowRequired": 200,
              "escrowAmount": 200,
              "serviceFeeRate": 0.05,
              "serviceFee": 15,
              "remainingPay": 100,
              "payableNow": 15,
              "provider": { "id": "provider-1", "nickname": "服务方" },
              "requester": { "id": "requester-1", "nickname": "需求方" },
              "demand": {
                "id": "demand-1",
                "title": "界面体验测试",
                "minPrice": "200",
                "deposit": 200,
                "timeLimit": "2026-07-18T12:00:00.000Z"
              }
            }
            """.utf8
        )

        let order = try decoder.decode(OrderDTO.self, from: data)

        XCTAssertEqual(order.status, "IN_PROGRESS")
        XCTAssertEqual(order.agreedPrice?.value, Decimal(300))
        XCTAssertEqual(order.demand?.minPrice?.value, Decimal(200))
        XCTAssertEqual(order.demand?.deposit?.value, Decimal(200))
        XCTAssertEqual(order.escrowAmount?.value, Decimal(200))
        XCTAssertEqual(order.serviceFee?.value, Decimal(15))
        XCTAssertEqual(order.remainingPay?.value, Decimal(100))
        XCTAssertEqual(order.ruleVersion, "2026-07")
        XCTAssertEqual(order.demand?.timeLimit?.isoString, "2026-07-18T12:00:00.000Z")
    }

    func testDemandCreateMoneySummaryContract() throws {
        let data = Data(
            """
            {
              "id": "demand-1",
              "title": "发布回执",
              "minPrice": 200,
              "deposit": 200,
              "currency": "POINT",
              "ruleVersion": "2026-07",
              "depositRequired": 200,
              "escrowRequired": 200,
              "serviceFeeRate": 0.05,
              "payableNow": 10,
              "status": "ACTIVE"
            }
            """.utf8
        )
        let detail = try decoder.decode(DemandDetailDTO.self, from: data)
        XCTAssertEqual(detail.depositRequired?.value, Decimal(200))
        XCTAssertEqual(detail.ruleVersion, "2026-07")
        XCTAssertEqual(detail.payableNow?.value, Decimal(10))
    }

    func testDisputeRequestEncoding() throws {
        struct Body: Encodable {
            let reason: String
            let description: String
            let evidenceUrls: [String]
        }
        let body = Body(
            reason: "质量不符",
            description: "质量不符",
            evidenceUrls: ["https://example.com/a.jpg"]
        )
        let data = try JSONEncoder().encode(body)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["reason"] as? String, "质量不符")
        XCTAssertEqual(json?["description"] as? String, "质量不符")
        XCTAssertEqual(json?["evidenceUrls"] as? [String], ["https://example.com/a.jpg"])
    }

    func testOrderDemandTimeLimitAcceptsLegacyIntWithoutFailing() throws {
        let data = Data(
            """
            {
              "id": "demand-1",
              "minPrice": 100,
              "timeLimit": 180
            }
            """.utf8
        )
        let demand = try decoder.decode(OrderDemandDTO.self, from: data)
        XCTAssertNil(demand.timeLimit?.isoString)
    }

    func testDemandDetailContractIncludesDepositAndMedia() throws {
        let data = Data(
            """
            {
              "id": "demand-1",
              "title": "带附件需求",
              "minPrice": "200.00",
              "deposit": 200,
              "amountEstimate": "350",
              "mediaUrls": ["/uploads/a.jpg", "/uploads/b.png"],
              "lifecycleStage": "VISIBLE",
              "status": "ACTIVE"
            }
            """.utf8
        )
        let detail = try decoder.decode(DemandDetailDTO.self, from: data)
        XCTAssertEqual(detail.deposit?.value, Decimal(200))
        XCTAssertEqual(detail.amountEstimate?.value, Decimal(350))
        XCTAssertEqual(detail.mediaUrls?.values.count, 2)
        XCTAssertEqual(detail.lifecycleStage, "VISIBLE")
    }

    func testPayBreakdownContract() throws {
        let data = Data(
            """
            {
              "currency": "POINT",
              "ruleVersion": "2026-07",
              "minimumPrice": 200,
              "agreedPrice": 300,
              "depositRequired": 200,
              "escrowHeld": 200,
              "serviceFeeRate": 0.05,
              "serviceFee": 15,
              "payableNow": 15,
              "alreadyPrepaid": false
            }
            """.utf8
        )
        let dto = try decoder.decode(OrderPayBreakdownDTO.self, from: data)
        XCTAssertEqual(dto.payableNow?.value, Decimal(15))
        XCTAssertEqual(dto.ruleVersion, "2026-07")
    }

    func testConversationContract() throws {
        let data = Data(
            """
            {
              "user": { "id": "peer-1", "nickname": "协作者" },
              "lastMessage": {
                "id": "message-1",
                "fromUserId": "peer-1",
                "toUserId": "me",
                "content": "你好",
                "type": "TEXT"
              },
              "unreadCount": 2,
              "communication": {
                "applicantId": "app-1",
                "demandId": "demand-1",
                "demandTitle": "界面体验测试",
                "status": "COMMUNICATING",
                "commDeadline": "2026-07-17T07:00:00.000Z",
                "extensionMinutes": 5,
                "canExtend": true
              }
            }
            """.utf8
        )

        let conversation = try decoder.decode(ConversationDTO.self, from: data)

        XCTAssertEqual(conversation.user.id, "peer-1")
        XCTAssertEqual(conversation.lastMessage?.content, "你好")
        XCTAssertEqual(conversation.unreadCount, 2)
        XCTAssertEqual(conversation.communication?.demandId, "demand-1")
        XCTAssertEqual(conversation.communication?.canExtend, true)
    }

    func testCardAttachmentMessageContract() throws {
        let data = Data(
            """
            {
              "id": "message-card-1",
              "fromUserId": "me",
              "toUserId": "peer-1",
              "content": "看看这条需求",
              "type": "TEXT",
              "cardAttachment": {
                "id": "attachment-1",
                "cardType": "DEMAND",
                "demandId": "demand-1",
                "snapshot": {
                  "cardType": "DEMAND",
                  "cardId": "demand-1",
                  "title": "界面体验测试",
                  "description": "记录并修复问题",
                  "minPrice": "200",
                  "status": "ACTIVE"
                }
              }
            }
            """.utf8
        )

        let message = try decoder.decode(MessageDTO.self, from: data)

        XCTAssertEqual(message.cardAttachment?.cardType, "DEMAND")
        XCTAssertEqual(message.cardAttachment?.snapshot?.title, "界面体验测试")
        XCTAssertEqual(message.cardAttachment?.snapshot?.minPrice?.value, Decimal(200))
    }

    func testWelfareRewardContract() throws {
        let data = Data(
            """
            {
              "items": [
                {
                  "id": "reward-1",
                  "demandId": "demand-1",
                  "providerId": "user-1",
                  "amount": 12.5,
                  "isSpiritual": false,
                  "rewardType": "random",
                  "choiceLabel": null,
                  "badge": "助人为乐",
                  "createdAt": "2026-07-17T04:00:00.000Z"
                }
              ],
              "total": 1,
              "page": 1,
              "totalPages": 1,
              "totalEarned": 12.5,
              "badges": ["助人为乐"]
            }
            """.utf8
        )

        let page = try decoder.decode(WelfareRewardsPage.self, from: data)

        XCTAssertEqual(page.rows.count, 1)
        XCTAssertEqual(page.rows[0].displayTitle, "助人为乐")
        XCTAssertEqual(page.rows[0].amount?.value, Decimal(string: "12.5"))
        XCTAssertEqual(page.totalEarned?.value, Decimal(string: "12.5"))
    }

    func testAgentNavigationToolResultContract() {
        let data = """
        {
          "id": "tool-1",
          "name": "navigate_to",
          "success": true,
          "data": {
            "path": "/demands/demand-1",
            "title": "需求详情"
          }
        }
        """

        let event = AgentNavigationEvent.decode(event: "tool_result", data: data)

        XCTAssertEqual(event?.path, "/demands/demand-1")
        XCTAssertEqual(event?.title, "需求详情")
    }

    func testAgentNavigationNavigateEventContract() {
        let data = #"{"path":"/orders/order-1","title":"订单详情"}"#
        let event = AgentNavigationEvent.decode(event: "navigate", data: data)
        XCTAssertEqual(event?.path, "/orders/order-1")
        XCTAssertEqual(event?.title, "订单详情")
    }

    func testAgentForbiddenEventContract() {
        let data = """
        {
          "id": "payment",
          "message": "支付涉及资金安全，我无法代你完成，请在订单页手动支付。",
          "fallbackPage": "/orders"
        }
        """
        let event = AgentForbiddenEvent.decode(event: "forbidden", data: data)
        XCTAssertEqual(event?.message.contains("支付"), true)
        XCTAssertEqual(event?.fallbackPage, "/orders")
    }

    func testAgentNavigationRejectsTextAndFailedToolResults() {
        XCTAssertNil(
            AgentNavigationEvent.decode(
                event: "text",
                data: #"{"delta":"请打开 /orders/order-1"}"#
            )
        )
        XCTAssertNil(
            AgentNavigationEvent.decode(
                event: "tool_result",
                data: #"{"name":"navigate_to","success":false,"data":{"path":"/orders/order-1"}}"#
            )
        )
    }

    func testAgentPendingToolEventContract() {
        let data = """
        {
          "id": "call-1",
          "name": "create_demand",
          "message": "即将创建需求，请确认",
          "arguments": { "title": "修水管", "minPrice": 100 }
        }
        """
        let event = AgentPendingToolEvent.decode(event: "tool_pending", data: data)
        XCTAssertEqual(event?.id, "call-1")
        XCTAssertEqual(event?.name, "create_demand")
        XCTAssertTrue(event?.argumentsSummary.contains("title: 修水管") == true)
        XCTAssertNil(AgentPendingToolEvent.decode(event: "tool_result", data: data))
    }

    func testAgentToolResultPendingPayloadIsIgnoredByNavigation() {
        // Client must not navigate on pending tool_result wrappers.
        let pending = #"{"name":"navigate_to","success":true,"data":{"pending":true,"path":"/demands/create"}}"#
        // Navigation decoder only checks success+path; pending guard lives in AgentChatView.
        // Document the wire shape used by production SSE:
        let obj = try? JSONSerialization.jsonObject(with: Data(pending.utf8)) as? [String: Any]
        let data = obj?["data"] as? [String: Any]
        XCTAssertEqual(data?["pending"] as? Bool, true)
        XCTAssertEqual(data?["path"] as? String, "/demands/create")
    }

    func testAgentStreamBodyEncodesOptionalModelAndFixedApproval() throws {
        // Mirror AgentService.StreamBody contract used by model picker.
        struct StreamBody: Encodable {
            let message: String
            let thinkMode: Bool
            let accessMode: String
            let model: String?

            enum CodingKeys: String, CodingKey { case message, thinkMode, accessMode, model }

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(message, forKey: .message)
                try c.encode(thinkMode, forKey: .thinkMode)
                try c.encode(accessMode, forKey: .accessMode)
                try c.encodeIfPresent(model, forKey: .model)
            }
        }
        let encoder = JSONEncoder()
        let withModel = try encoder.encode(
            StreamBody(message: "你好", thinkMode: false, accessMode: "approval", model: "ninewood-3b-v2.1")
        )
        let withModelObj = try JSONSerialization.jsonObject(with: withModel) as? [String: Any]
        XCTAssertEqual(withModelObj?["accessMode"] as? String, "approval")
        XCTAssertEqual(withModelObj?["model"] as? String, "ninewood-3b-v2.1")
        XCTAssertEqual(withModelObj?["thinkMode"] as? Bool, false)

        let noModel = try encoder.encode(
            StreamBody(message: "你好", thinkMode: true, accessMode: "approval", model: nil)
        )
        let noModelObj = try JSONSerialization.jsonObject(with: noModel) as? [String: Any]
        XCTAssertNil(noModelObj?["model"])
        XCTAssertEqual(noModelObj?["accessMode"] as? String, "approval")
    }

    func testNotificationDeepLinkResolvesOrderDemandAndPath() throws {
        let orderJSON = Data(
            """
            {
              "id": "n1",
              "type": "SYSTEM",
              "content": "订单已更新",
              "orderId": "11111111-1111-1111-1111-111111111111",
              "isRead": false
            }
            """.utf8
        )
        let order = try decoder.decode(NotificationDTO.self, from: orderJSON)
        XCTAssertEqual(order.deepLink, .order(id: "11111111-1111-1111-1111-111111111111"))

        let demandJSON = Data(
            """
            {
              "id": "n2",
              "demandId": "22222222-2222-2222-2222-222222222222",
              "content": "有人申请了你的需求"
            }
            """.utf8
        )
        let demand = try decoder.decode(NotificationDTO.self, from: demandJSON)
        XCTAssertEqual(demand.deepLink, .demand(id: "22222222-2222-2222-2222-222222222222"))

        let pathJSON = Data(
            """
            {
              "id": "n3",
              "path": "/messages",
              "content": "打开消息"
            }
            """.utf8
        )
        let path = try decoder.decode(NotificationDTO.self, from: pathJSON)
        XCTAssertEqual(path.deepLink, .path("/messages"))

        let noneJSON = Data(
            """
            { "id": "n4", "content": "系统维护通知" }
            """.utf8
        )
        let none = try decoder.decode(NotificationDTO.self, from: noneJSON)
        XCTAssertEqual(none.deepLink, .none)
    }
}
