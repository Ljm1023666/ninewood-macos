import Foundation

@MainActor
final class DemandService {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func searchDemands(page: Int = 1, limit: Int = 20) async throws -> [Demand] {
        let pageData: DemandsSearchResult = try await client.get(
            "/demands/search",
            query: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "stage", value: "active"),
            ]
        )
        return pageData.demands.map(DemandMapper.mapListItem)
    }

    /// 卡池进行中（对齐 Windows `/demands/active`）
    func poolActive(page: Int = 1, pageSize: Int = 20) async throws -> [Demand] {
        let pageData: DemandsSearchResult = try await client.get(
            "/demands/active",
            query: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "pageSize", value: String(pageSize)),
            ]
        )
        return pageData.demands.map(DemandMapper.mapListItem)
    }

    /// 卡池死池 / 过期（对齐 Windows `/demands/dead`）
    func poolDead(page: Int = 1, pageSize: Int = 20) async throws -> [Demand] {
        let pageData: DemandsSearchResult = try await client.get(
            "/demands/dead",
            query: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "pageSize", value: String(pageSize)),
            ]
        )
        return pageData.demands.map(DemandMapper.mapListItem)
    }

    func getDemand(id: String) async throws -> Demand {
        let dto: DemandDetailDTO = try await client.get("/demands/\(id)")
        return DemandMapper.mapDetail(dto)
    }

    func getDemandSnapshot(id: String) async throws -> DemandDetailSnapshot {
        let dto: DemandDetailDTO = try await client.get("/demands/\(id)")
        return DemandDetailSnapshot(
            demand: DemandMapper.mapDetail(dto),
            applicants: (dto.applicantsV2 ?? []).map(DemandMapper.mapApplicant)
        )
    }

    func createDemand(
        title: String,
        description: String,
        expectedOutcome: String,
        minPrice: Decimal,
        expectedPrice: Decimal? = nil,
        category: String = "日常服务",
        serviceType: String = "OFFLINE",
        expireAt: Date = Date().addingTimeInterval(15 * 60),
        maxApplicants: Int = 10,
        isCertifiedOnly: Bool = false,
        tags: [String] = [],
        regionId: Int? = nil,
        timeLimitMinutes: Int? = nil,
        files: [MultipartFile] = [],
        idempotencyKey: String
    ) async throws -> DemandDetailDTO {
        let formatter = ISO8601DateFormatter()
        var fields: [String: String] = [
            "title": title,
            "description": description,
            "expectedOutcome": expectedOutcome,
            "minPrice": "\(minPrice)",
            "category": category,
            "serviceType": serviceType,
            "expireAt": formatter.string(from: expireAt),
            "maxApplicants": "\(maxApplicants)",
            "isCertifiedOnly": isCertifiedOnly ? "true" : "false",
            "visibilityWindow": "15",
        ]
        if let expectedPrice {
            fields["amountEstimate"] = "\(expectedPrice)"
        }
        if !tags.isEmpty {
            fields["tags"] = tags.joined(separator: ",")
            fields["tagsConfirmed"] = "true"
        }
        if let regionId {
            fields["regionId"] = String(regionId)
        }
        if let timeLimitMinutes {
            fields["timeLimitMinutes"] = String(timeLimitMinutes)
        }
        return try await client.postMultipart(
            "/demands",
            fields: fields,
            files: files,
            idempotencyKey: idempotencyKey
        )
    }

    /// 请求接单（两段式第一阶段）
    func requestApply(id: String, message: String, idempotencyKey: String) async throws -> DemandApplicantDTO {
        try await client.post(
            "/demands/\(id)/request",
            body: DemandRequestBody(message: message),
            idempotencyKey: idempotencyKey
        )
    }

    func myDemands(page: Int = 1) async throws -> [Demand] {
        // 后端 `/demands/my` 可能返回分页结构；尽量兼容 demands / items
        struct FlexiblePage: Decodable {
            let demands: [DemandListItemDTO]?
            let items: [DemandListItemDTO]?
        }
        let pageData: FlexiblePage = try await client.get(
            "/demands/my",
            query: [URLQueryItem(name: "page", value: String(page))]
        )
        let rows = pageData.demands ?? pageData.items ?? []
        return rows.map(DemandMapper.mapListItem)
    }

    func withdraw(id: String) async throws {
        struct OK: Decodable {}
        let _: OK = try await client.post("/demands/\(id)/withdraw")
    }

    func applicants(demandId: String) async throws -> [DemandApplicant] {
        let rows: [DemandApplicantDTO] = try await client.get("/demands/\(demandId)/applicants-v2")
        return rows.map(DemandMapper.mapApplicant)
    }

    func acceptApplicant(
        demandId: String,
        applicantId: String,
        idempotencyKey: String
    ) async throws -> DemandAcceptResultDTO {
        try await client.post(
            "/demands/\(demandId)/accept/\(applicantId)",
            idempotencyKey: idempotencyKey
        )
    }

    func rejectApplicant(
        demandId: String,
        applicantId: String,
        idempotencyKey: String
    ) async throws {
        let _: OperationResultDTO = try await client.post(
            "/demands/\(demandId)/reject/\(applicantId)",
            idempotencyKey: idempotencyKey
        )
    }

    /// 卡池应标（对齐 Windows `/demands/:id/bid`）
    func bid(id: String, offerPrice: Decimal?, message: String) async throws {
        struct Body: Encodable {
            let offerPrice: Double?
            let message: String
        }
        struct OK: Decodable {}
        let _: OK = try await client.post(
            "/demands/\(id)/bid",
            body: Body(
                offerPrice: offerPrice.map { NSDecimalNumber(decimal: $0).doubleValue },
                message: message
            ),
            idempotencyKey: UUID().uuidString
        )
    }

    func bids(id: String) async throws -> [DemandBidDTO] {
        try await client.get("/demands/\(id)/bids")
    }

    func myApplications(page: Int = 1) async throws -> [Demand] {
        struct Page: Decodable {
            let demands: [DemandListItemDTO]?
            let items: [DemandListItemDTO]?
            let applications: [DemandListItemDTO]?
        }
        let pageData: Page = try await client.get(
            "/demands/my-applications",
            query: [URLQueryItem(name: "page", value: String(page))]
        )
        let rows = pageData.demands ?? pageData.items ?? pageData.applications ?? []
        return rows.map(DemandMapper.mapListItem)
    }

    func snatch(id: String) async throws {
        struct OK: Decodable {}
        let _: OK = try await client.post("/demands/\(id)/snatch")
    }

    func deleteDemand(id: String) async throws {
        struct OK: Decodable {}
        let _: OK = try await client.delete("/demands/\(id)")
    }
}

enum DemandMapper {
    static func mapListItem(_ dto: DemandListItemDTO) -> Demand {
        let minPrice = dto.minPrice?.value ?? 0
        let expected = dto.expectedPrice?.value
        let applicantCount = dto.applicantCount ?? 0
        let applicantLimit = dto.maxApplicants ?? 10
        let body = dto.expectedOutcome
            ?? dto.descriptionPreview
            ?? dto.description
            ?? "暂无预期结果说明"
        let distanceKm = dto.distance ?? dto.distanceKm
        let deadline = dto.expireAt ?? dto.deadlineAt

        return Demand(
            id: dto.id,
            title: dto.title,
            expectedOutcome: body,
            minPrice: minPrice,
            expectedPrice: expected,
            distanceText: distanceText(for: distanceKm, serviceType: dto.serviceType),
            countdownText: countdownText(from: deadline),
            applicantCount: applicantCount,
            applicantLimit: applicantLimit,
            tags: tags(from: dto),
            state: state(applicantCount: applicantCount, applicantLimit: applicantLimit, deadlineAt: deadline),
            publisher: AppUser.from(dto.user),
            deadlineText: deadlineText(from: deadline),
            isCertifiedOnly: dto.isCertifiedOnly ?? false,
            allowNearby: dto.serviceType != "ONLINE",
            status: DemandStatus(rawValue: dto.status),
            visibleUntil: APIDate.parse(deadline),
            coverImageUrl: dto.coverImage ?? dto.coverUrl
        )
    }

    static func mapDetail(_ dto: DemandDetailDTO) -> Demand {
        let applicantCount = dto.applicantCount ?? 0
        let applicantLimit = dto.maxApplicants ?? 10
        return Demand(
            id: dto.id,
            title: dto.title,
            expectedOutcome: dto.expectedOutcome ?? dto.description ?? "暂无预期结果说明",
            minPrice: dto.minPrice?.value ?? 0,
            expectedPrice: nil,
            distanceText: dto.serviceType == "ONLINE" ? "线上服务" : "附近",
            countdownText: countdownText(from: dto.expireAt),
            applicantCount: applicantCount,
            applicantLimit: applicantLimit,
            tags: {
                var t = dto.tags ?? []
                if let tag = dto.tagName, !tag.isEmpty { t.insert(tag, at: 0) }
                if let category = dto.category { t.append(category) }
                return Array(Set(t))
            }(),
            state: state(applicantCount: applicantCount, applicantLimit: applicantLimit, deadlineAt: dto.expireAt),
            publisher: AppUser.from(dto.user),
            deadlineText: deadlineText(from: dto.expireAt),
            isCertifiedOnly: dto.isCertifiedOnly ?? false,
            allowNearby: dto.serviceType != "ONLINE",
            status: DemandStatus(rawValue: dto.status),
            visibleUntil: APIDate.parse(dto.visibleUntil ?? dto.expireAt),
            isOwner: dto.isOwner ?? false,
            hasRequested: (dto.applicantsV2 ?? []).contains { $0.userId != dto.user?.id },
            hasOrder: dto.hasOrder ?? false,
            coverImageUrl: dto.coverImage ?? dto.coverUrl
        )
    }

    static func mapApplicant(_ dto: DemandApplicantDTO) -> DemandApplicant {
        DemandApplicant(
            id: dto.id,
            user: AppUser.from(dto.user),
            message: dto.message ?? "未填写说明",
            status: dto.status,
            createdAt: APIDate.parse(dto.createdAt),
            communicationDeadline: APIDate.parse(dto.commDeadline)
        )
    }

    private static func mapUser(_ user: SoftUserDTO?) -> AppUser {
        AppUser.from(user)
    }

    private static func tags(from dto: DemandListItemDTO) -> [String] {
        var tags = dto.tags ?? []
        if let tag = dto.tagName, !tag.isEmpty { tags.append(tag) }
        if let category = dto.category, !category.isEmpty { tags.append(category) }
        if dto.serviceType == "ONLINE" { tags.append("线上") }
        if dto.serviceType == "OFFLINE" { tags.append("线下") }
        return tags.reduce(into: []) { result, tag in
            if !tag.isEmpty, !result.contains(tag) { result.append(tag) }
        }
    }

    private static func distanceText(for km: Double?, serviceType: String?) -> String {
        if serviceType == "ONLINE" { return "线上服务" }
        guard let km else { return "附近" }
        if km < 1 { return "约 \(Int(km * 1000))m" }
        return String(format: "约 %.1fkm", km)
    }

    private static func deadlineText(from iso: String?) -> String {
        guard let date = APIDate.parse(iso) else { return "待确认" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private static func countdownText(from iso: String?) -> String {
        guard let deadline = APIDate.parse(iso) else { return "—" }
        let remaining = max(0, Int(deadline.timeIntervalSinceNow))
        if remaining <= 0 { return "已截止" }
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        if hours > 0 { return "剩余 \(hours)h \(minutes)m" }
        return "剩余 \(minutes)m"
    }

    private static func state(applicantCount: Int, applicantLimit: Int, deadlineAt: String?) -> Demand.State {
        if applicantCount >= applicantLimit { return .full }
        if let deadline = APIDate.parse(deadlineAt), deadline.timeIntervalSinceNow < 3600 {
            return .urgent
        }
        return .normal
    }
}

struct DemandDetailSnapshot {
    let demand: Demand
    let applicants: [DemandApplicant]
}

enum APIDate {
    static func parse(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: iso) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: iso)
    }

    static func relativeOrTime(_ iso: String?) -> String {
        guard let date = parse(iso) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "M/d"
        }
        return formatter.string(from: date)
    }
}
