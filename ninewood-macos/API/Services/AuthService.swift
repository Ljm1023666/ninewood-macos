import Foundation

struct LoginRequest: Encodable {
    let phone: String
    let password: String
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

    func fetchCurrentUser() async throws -> UserDTO {
        try await client.get("/auth/me")
    }

    func logout() async {
        struct LogoutOK: Decodable { let ok: Bool? }
        _ = try? await client.post("/auth/logout") as LogoutOK
        client.setAuthToken(nil)
    }
}
