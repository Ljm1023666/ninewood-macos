import Foundation

@MainActor
final class UserService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func me() async throws -> SoftUserDTO {
        try await client.get("/users/me")
    }

    func get(id: String) async throws -> SoftUserDTO {
        try await client.get("/users/\(id)")
    }

    func search(keyword: String) async throws -> [SoftUserDTO] {
        struct UsersWrap: Decodable { let users: [SoftUserDTO]? }
        if let rows: [SoftUserDTO] = try? await client.get(
            "/users/search",
            query: [URLQueryItem(name: "keyword", value: keyword)]
        ) {
            return rows
        }
        let wrap: UsersWrap = try await client.get(
            "/users/search",
            query: [URLQueryItem(name: "keyword", value: keyword)]
        )
        return wrap.users ?? []
    }

    func searchByTags(_ tags: String, regionId: Int? = nil, page: Int = 1) async throws -> [SoftUserDTO] {
        var query = [
            URLQueryItem(name: "tags", value: tags),
            URLQueryItem(name: "page", value: String(page)),
        ]
        if let regionId { query.append(URLQueryItem(name: "regionId", value: String(regionId))) }
        if let rows: [SoftUserDTO] = try? await client.get("/users/search", query: query) {
            return rows
        }
        let pageData: UserListPage = try await client.get("/users/search", query: query)
        return pageData.rows
    }

    func follow(id: String) async throws {
        struct OK: Decodable {}
        let _: OK = try await client.post("/users/\(id)/follow")
    }

    func unfollow(id: String) async throws {
        struct OK: Decodable {}
        let _: OK = try await client.delete("/users/\(id)/follow")
    }

    func followers(id: String, page: Int = 1) async throws -> [SoftUserDTO] {
        let pageData: UserListPage = try await client.get(
            "/users/\(id)/followers",
            query: [URLQueryItem(name: "page", value: String(page))]
        )
        return pageData.rows
    }

    func following(id: String, page: Int = 1) async throws -> [SoftUserDTO] {
        let pageData: UserListPage = try await client.get(
            "/users/\(id)/following",
            query: [URLQueryItem(name: "page", value: String(page))]
        )
        return pageData.rows
    }

    func toggleFavorite(demandId: String) async throws {
        struct OK: Decodable {}
        let _: OK = try await client.post("/users/favorites/\(demandId)")
    }

    func favorites(page: Int = 1) async throws -> DemandsSearchResult {
        try await client.get(
            "/users/favorites",
            query: [URLQueryItem(name: "page", value: String(page))]
        )
    }

    func updateProfile(nickname: String?, bio: String?) async throws -> SoftUserDTO {
        struct Body: Encodable {
            let nickname: String?
            let bio: String?
        }
        return try await client.put("/users/profile", body: Body(nickname: nickname, bio: bio))
    }

    func updateProfileMultipart(
        nickname: String? = nil,
        bio: String? = nil,
        avatar: MultipartFile? = nil,
        cover: MultipartFile? = nil
    ) async throws -> SoftUserDTO {
        var fields: [String: String] = [:]
        if let nickname { fields["nickname"] = nickname }
        if let bio { fields["bio"] = bio }
        var files: [MultipartFile] = []
        if let avatar { files.append(avatar) }
        if let cover { files.append(cover) }
        return try await client.putMultipart("/users/profile", fields: fields, files: files)
    }

    func toggleFavoriteCard(cardId: String) async throws {
        struct OK: Decodable { let favorited: Bool? }
        let _: OK = try await client.post("/users/favorites/cards/\(cardId)")
    }

    func favoriteCards(page: Int = 1) async throws -> [ServiceCardDTO] {
        struct Page: Decodable {
            let cards: [ServiceCardDTO]?
            let items: [ServiceCardDTO]?
        }
        let pageData: Page = try await client.get(
            "/users/favorites/cards",
            query: [URLQueryItem(name: "page", value: String(page))]
        )
        return pageData.cards ?? pageData.items ?? []
    }

    func myTags() async throws -> [String] {
        struct TagsDTO: Decodable { let tags: [String]? }
        let dto: TagsDTO = try await client.get("/users/tags")
        return dto.tags ?? []
    }

    func updateTags(_ tags: [String]) async throws {
        struct Body: Encodable { let tags: [String] }
        struct OK: Decodable {}
        let _: OK = try await client.put("/users/tags", body: Body(tags: tags))
    }

    func busyStatus() async throws -> BusyStatusDTO {
        try await client.get("/users/busy")
    }

    func updateBusy(isBusy: Bool, allowSpecialSearch: Bool? = nil) async throws {
        struct Body: Encodable {
            let isBusy: Bool
            let allowSpecialSearch: Bool?
        }
        struct OK: Decodable {}
        let _: OK = try await client.put("/users/busy", body: Body(isBusy: isBusy, allowSpecialSearch: allowSpecialSearch))
    }

    func fetchBlocklist() async throws -> (tags: [String], keywords: [String]) {
        struct BL: Decodable {
            let tags: [String]?
            let keywords: [String]?
        }
        let dto: BL = try await client.get("/users/blocklist")
        return (dto.tags ?? [], dto.keywords ?? [])
    }

    func updateBlocklist(tags: [String], keywords: [String]) async throws {
        struct Body: Encodable {
            let tags: [String]
            let keywords: [String]
        }
        struct OK: Decodable {}
        let _: OK = try await client.put("/users/blocklist", body: Body(tags: tags, keywords: keywords))
    }

    func snatchStatus() async throws -> SnatchStatusDTO {
        try await client.get("/users/snatch-status")
    }

    func fetchPushPreferences() async throws -> PushPreferenceDTO {
        try await client.get("/pushes/preferences")
    }

    func updatePushPreferences(
        receivePushes: Bool? = nil,
        pushFrequency: String? = nil,
        excludeKeywords: [String]? = nil,
        excludeTags: [String]? = nil,
        excludeRegions: [Int]? = nil
    ) async throws -> PushPreferenceDTO {
        struct Body: Encodable {
            let receivePushes: Bool?
            let pushFrequency: String?
            let excludeKeywords: [String]?
            let excludeTags: [String]?
            let excludeRegions: [Int]?
        }
        return try await client.put(
            "/pushes/preferences",
            body: Body(
                receivePushes: receivePushes,
                pushFrequency: pushFrequency,
                excludeKeywords: excludeKeywords,
                excludeTags: excludeTags,
                excludeRegions: excludeRegions
            )
        )
    }
}
