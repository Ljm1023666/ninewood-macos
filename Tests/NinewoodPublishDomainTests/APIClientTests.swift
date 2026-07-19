import Foundation
import XCTest
@testable import NinewoodAPIContracts

@MainActor
final class APIClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testPostSendsAuthRequestAndIdempotencyHeaders() async throws {
        let tokenStore = MemoryTokenStore(token: "test-token")
        let client = makeClient(tokenStore: tokenStore)
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "stable-key")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Request-ID"))
            return Self.response(
                request,
                status: 200,
                headers: ["X-Request-ID": "server-request"],
                body: #"{"code":200,"message":"ok","data":{"value":"done"},"timestamp":null,"requestId":"envelope-request"}"#
            )
        }

        let result: TestPayload = try await client.post(
            "/test",
            body: TestBody(name: "ninewood"),
            idempotencyKey: "stable-key"
        )

        XCTAssertEqual(result.value, "done")
        XCTAssertEqual(client.latestRequestID, "envelope-request")
    }

    func testUnauthorizedClearsTokenAndNotifiesSession() async {
        let tokenStore = MemoryTokenStore(token: "expired-token")
        let client = makeClient(tokenStore: tokenStore)
        var unauthorizedCount = 0
        client.onUnauthorized = { unauthorizedCount += 1 }
        URLProtocolStub.handler = { request in
            Self.response(request, status: 401, body: #"{"message":"expired"}"#)
        }

        do {
            let _: TestPayload = try await client.get("/protected")
            XCTFail("Expected unauthorized")
        } catch APIError.unauthorized {
            XCTAssertNil(client.authToken)
            XCTAssertNil(tokenStore.token)
            XCTAssertEqual(tokenStore.deleteCount, 1)
            XCTAssertEqual(unauthorizedCount, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRateLimitUsesRetryAfterAndBlocksFollowingWriteLocally() async {
        let client = makeClient()
        var requestCount = 0
        URLProtocolStub.handler = { request in
            requestCount += 1
            return Self.response(
                request,
                status: 429,
                headers: ["Retry-After": "12", "X-Request-ID": "rate-request"],
                body: #"{"message":"slow down"}"#
            )
        }

        await assertRateLimited(retryAfter: 12, requestID: "rate-request") {
            let _: TestPayload = try await client.post("/write")
        }
        await assertRateLimited(requestID: "rate-request") {
            let _: TestPayload = try await client.post("/write")
        }
        XCTAssertEqual(requestCount, 1)
        XCTAssertNotNil(client.rateLimitedUntil)
    }

    func testServerErrorPreservesCodeMessageAndRequestID() async {
        let client = makeClient()
        URLProtocolStub.handler = { request in
            Self.response(
                request,
                status: 422,
                headers: ["X-Request-ID": "header-request"],
                body: #"{"code":422,"error":"INVALID_STATE","message":"状态不允许","requestId":"body-request"}"#
            )
        }

        do {
            let _: TestPayload = try await client.get("/failure")
            XCTFail("Expected server error")
        } catch let APIError.server(statusCode, errorCode, message, requestID) {
            XCTAssertEqual(statusCode, 422)
            XCTAssertEqual(errorCode, "INVALID_STATE")
            XCTAssertEqual(message, "状态不允许")
            XCTAssertEqual(requestID, "body-request")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRawResponseDecodesWithoutEnvelope() async throws {
        let client = makeClient()
        URLProtocolStub.handler = { request in
            Self.response(
                request,
                status: 200,
                headers: ["X-Request-ID": "raw-request"],
                body: #"{"value":"raw"}"#
            )
        }

        let result: TestPayload = try await client.getRaw("/raw")

        XCTAssertEqual(result.value, "raw")
        XCTAssertEqual(client.latestRequestID, "raw-request")
    }

    func testEnvelopeFailureIsReportedEvenWhenHTTPStatusIsSuccessful() async {
        let client = makeClient()
        URLProtocolStub.handler = { request in
            Self.response(
                request,
                status: 200,
                body: #"{"code":409,"message":"业务状态冲突","data":null,"timestamp":null,"requestId":"business-request"}"#
            )
        }

        do {
            let _: TestPayload = try await client.get("/business-failure")
            XCTFail("Expected business error")
        } catch let APIError.server(statusCode, _, message, requestID) {
            XCTAssertEqual(statusCode, 200)
            XCTAssertEqual(message, "业务状态冲突")
            XCTAssertEqual(requestID, "business-request")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDecodingFailurePreservesResponseRequestID() async {
        let client = makeClient()
        URLProtocolStub.handler = { request in
            Self.response(
                request,
                status: 200,
                headers: ["X-Request-ID": "decode-request"],
                body: #"{"code":200,"message":"ok","data":{"unexpected":true},"timestamp":null,"requestId":null}"#
            )
        }

        do {
            let _: TestPayload = try await client.get("/invalid-contract")
            XCTFail("Expected decoding error")
        } catch let APIError.decoding(_, requestID) {
            XCTAssertEqual(requestID, "decode-request")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testReadRequestStillRunsDuringWriteCooldown() async throws {
        let client = makeClient()
        var requestCount = 0
        URLProtocolStub.handler = { request in
            requestCount += 1
            if request.httpMethod == "POST" {
                return Self.response(
                    request,
                    status: 429,
                    headers: ["Retry-After": "10"],
                    body: #"{"message":"slow down"}"#
                )
            }
            return Self.response(
                request,
                status: 200,
                body: #"{"code":200,"message":"ok","data":{"value":"read"},"timestamp":null,"requestId":null}"#
            )
        }

        await assertRateLimited {
            let _: TestPayload = try await client.post("/write")
        }
        let result: TestPayload = try await client.get("/read")

        XCTAssertEqual(result.value, "read")
        XCTAssertEqual(requestCount, 2)
    }

    func testHealthCheckAcceptsDegradedServiceState() async throws {
        let client = makeClient()
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/health/services")
            return Self.response(
                request,
                status: 200,
                body: #"{"status":"degraded"}"#
            )
        }

        let isHealthy = try await client.healthCheck()
        XCTAssertTrue(isHealthy)
    }

    func testHealthCheckFallsBackToAuthProbe() async throws {
        let client = makeClient()
        var paths: [String] = []
        URLProtocolStub.handler = { request in
            paths.append(request.url?.path ?? "")
            if request.url?.path == "/api/health/services" {
                return Self.response(request, status: 503, body: #"{"message":"starting"}"#)
            }
            return Self.response(request, status: 401, body: #"{"message":"unauthorized"}"#)
        }

        let isHealthy = try await client.healthCheck()
        XCTAssertTrue(isHealthy)
        XCTAssertEqual(paths, ["/api/health/services", "/api/auth/me"])
    }

    func testHealthCheckDoesNotHideRateLimitBehindFallbackProbe() async {
        let client = makeClient()
        var requestCount = 0
        URLProtocolStub.handler = { request in
            requestCount += 1
            return Self.response(
                request,
                status: 429,
                headers: ["Retry-After": "8", "X-Request-ID": "health-rate"],
                body: #"{"message":"slow down"}"#
            )
        }

        await assertRateLimited(retryAfter: 8, requestID: "health-rate") {
            _ = try await client.healthCheck()
        }
        XCTAssertEqual(requestCount, 1)
    }

    func testMultipartSanitizesDispositionAndKeepsIdempotencyKey() async throws {
        let client = makeClient()
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "upload-key")
            XCTAssertTrue(
                request.value(forHTTPHeaderField: "Content-Type")?
                    .hasPrefix("multipart/form-data; boundary=Boundary-") == true
            )
            let body = String(data: Self.bodyData(from: request), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains(#"name="caption""#))
            XCTAssertTrue(body.contains(#"filename="bad__name_.jpg""#))
            XCTAssertFalse(body.contains("\r\nInjected:"))
            XCTAssertTrue(body.contains("binary-content"))
            return Self.response(
                request,
                status: 200,
                body: #"{"code":200,"message":"ok","data":{"value":"uploaded"},"timestamp":null,"requestId":null}"#
            )
        }

        let result: TestPayload = try await client.postMultipart(
            "/upload",
            fields: ["caption": "证据"],
            files: [
                MultipartFile(
                    fieldName: "file",
                    fileName: "bad\r\nname\".jpg",
                    mimeType: "image/jpeg",
                    data: Data("binary-content".utf8)
                )
            ],
            idempotencyKey: "upload-key"
        )

        XCTAssertEqual(result.value, "uploaded")
    }

    private func makeClient(tokenStore: MemoryTokenStore = MemoryTokenStore()) -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return APIClient(session: URLSession(configuration: configuration), tokenStore: tokenStore)
    }

    private func assertRateLimited(
        retryAfter: TimeInterval? = nil,
        requestID: String? = nil,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected rate limit")
        } catch let APIError.rateLimited(actualRetryAfter, actualRequestID) {
            if let retryAfter {
                XCTAssertEqual(actualRetryAfter ?? 0, retryAfter, accuracy: 0.1)
            }
            XCTAssertEqual(actualRequestID, requestID)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private static func response(
        _ request: URLRequest,
        status: Int,
        headers: [String: String] = [:],
        body: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        return (response, Data(body.utf8))
    }

    private static func bodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 4096)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private struct TestBody: Encodable {
    let name: String
}

private struct TestPayload: Decodable {
    let value: String
}

private final class MemoryTokenStore: APITokenStore {
    var token: String?
    private(set) var deleteCount = 0

    init(token: String? = nil) {
        self.token = token
    }

    func load() -> String? { token }
    func save(_ token: String) { self.token = token }
    func delete() {
        token = nil
        deleteCount += 1
    }
}

private final class URLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
