import Foundation

struct LoginRequest: Encodable {
    let phone: String
    let password: String
}

struct SendCodeRequest: Encodable {
    let phone: String
    let captchaToken: String
}

struct SendCodeResultDTO: Decodable {
    let phone: String?
    /// 仅在短信通道未配置时由服务端回传（临时策略）
    let code: String?
    let delivery: String?
}

struct RegisterRequest: Encodable {
    let phone: String
    let code: String
    let password: String
    let birthday: String
    let guardianConsent: Bool?
}

@MainActor
final class AuthService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func login(phone: String, password: String) async throws -> UserDTO {
        let payload: AuthPayloadDTO = try await client.post(
            "/auth/login",
            body: LoginRequest(phone: phone, password: password)
        )
        client.setAuthToken(payload.token)
        return payload.user
    }

    func sendCode(phone: String, captchaToken: String) async throws -> SendCodeResultDTO {
        try await client.post(
            "/auth/send-code",
            body: SendCodeRequest(phone: phone, captchaToken: captchaToken)
        )
    }

    func register(
        phone: String,
        code: String,
        password: String,
        birthday: String,
        guardianConsent: Bool?
    ) async throws -> UserDTO {
        let payload: AuthPayloadDTO = try await client.post(
            "/auth/register",
            body: RegisterRequest(
                phone: phone,
                code: code,
                password: password,
                birthday: birthday,
                guardianConsent: guardianConsent
            )
        )
        client.setAuthToken(payload.token)
        return payload.user
    }

    func fetchCurrentUser() async throws -> UserDTO {
        try await client.get("/auth/me")
    }

    func logout() async {
        struct LogoutOK: Decodable { let ok: Bool? }
        _ = try? await client.post("/auth/logout") as LogoutOK
        client.setAuthToken(nil)
    }

    func sendResetCode(phone: String, captchaToken: String) async throws -> SendCodeResultDTO {
        try await client.post(
            "/auth/send-reset-code",
            body: SendCodeRequest(phone: phone, captchaToken: captchaToken)
        )
    }

    func resetPassword(phone: String, code: String, newPassword: String) async throws {
        struct Body: Encodable {
            let phone: String
            let code: String
            let newPassword: String
        }
        struct OK: Decodable { let ok: Bool? }
        let _: OK = try await client.post(
            "/auth/reset-password",
            body: Body(phone: phone, code: code, newPassword: newPassword)
        )
    }
}
