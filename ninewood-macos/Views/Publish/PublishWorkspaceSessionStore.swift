import Foundation

enum PublishWorkspaceKind: String, Codable, Sendable {
    case demand
    case service
}

/// 对齐 Windows `demand-session-history.ts`：本地多会话草稿。
struct PublishWorkspaceSessionSnapshot: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var updatedAt: TimeInterval
    var messages: [PublishWorkspaceChatMessageDTO]
    var input: String
    var fields: PublishWorkspaceFieldsDTO
    var fieldOverrides: [String]
    var lockedKeywords: [String]
    var missingInfo: [String]
    var missingQueue: PublishMissingQueueState
    var confidence: String
    var readyToPublish: Bool
    var speedMode: Bool
}

struct PublishWorkspaceChatMessageDTO: Codable, Equatable, Sendable {
    var id: String
    var role: String
    var content: String
    var toolArgs: [String: String]?
    var reasoningContent: String?

    init(_ msg: PublishWorkspaceChatMessage) {
        id = msg.id
        role = msg.role
        content = msg.content
        toolArgs = msg.toolArgs
        reasoningContent = msg.reasoningContent
    }

    init(
        id: String,
        role: String,
        content: String,
        toolArgs: [String: String]? = nil,
        reasoningContent: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolArgs = toolArgs
        self.reasoningContent = reasoningContent
    }

    func toMessage() -> PublishWorkspaceChatMessage {
        .init(
            id: id,
            role: role,
            content: content,
            toolArgs: toolArgs,
            reasoningContent: reasoningContent
        )
    }
}

struct PublishWorkspaceFieldsDTO: Codable, Equatable, Sendable {
    var title: String
    var description: String
    var serviceType: String?
    var budget: String
    var schedule: String
    var category: String
    var regionId: Int?
    var expectedOutcome: String
    var scopeLabels: [String]
    var suggestedKeywords: [String]
    var confidence: String
    var taxonomyLeafId: String?
    var missingInfo: [String]
    var readyToPublish: Bool
    var visibilityWindow: Int
    var maxApplicants: Int
    var timeLimitMinutes: Int?

    init(_ f: PublishWorkspaceFields) {
        title = f.title
        description = f.description
        serviceType = f.serviceType
        budget = f.budget
        schedule = f.schedule
        category = f.category
        regionId = f.regionId
        expectedOutcome = f.expectedOutcome
        scopeLabels = f.scopeLabels
        suggestedKeywords = f.suggestedKeywords
        confidence = f.confidence
        taxonomyLeafId = f.taxonomyLeafId
        missingInfo = f.missingInfo
        readyToPublish = f.readyToPublish
        visibilityWindow = f.visibilityWindow
        maxApplicants = f.maxApplicants
        timeLimitMinutes = f.timeLimitMinutes
    }

    func toFields() -> PublishWorkspaceFields {
        var f = PublishWorkspaceFields()
        f.title = title
        f.description = description
        f.serviceType = serviceType
        f.budget = budget
        f.schedule = schedule
        f.category = category
        f.regionId = regionId
        f.expectedOutcome = expectedOutcome
        f.scopeLabels = scopeLabels
        f.suggestedKeywords = suggestedKeywords
        f.confidence = confidence
        f.taxonomyLeafId = taxonomyLeafId
        f.missingInfo = missingInfo
        f.readyToPublish = readyToPublish
        f.visibilityWindow = visibilityWindow
        f.maxApplicants = maxApplicants
        f.timeLimitMinutes = timeLimitMinutes
        return f
    }
}

enum PublishWorkspaceSessionStore {
    private static let maxSessions = 40

    private static func storageKey(kind: PublishWorkspaceKind) -> String {
        kind == .service ? "ninewood_service_sessions_v2" : "ninewood_demand_sessions_v2"
    }

    private static func activeKey(kind: PublishWorkspaceKind) -> String {
        kind == .service ? "ninewood_service_active_v2" : "ninewood_demand_active_v2"
    }

    static func list(kind: PublishWorkspaceKind) -> [PublishWorkspaceSessionSnapshot] {
        guard let data = UserDefaults.standard.data(forKey: storageKey(kind: kind)),
              let list = try? JSONDecoder().decode([PublishWorkspaceSessionSnapshot].self, from: data)
        else { return [] }
        return list.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func activeId(kind: PublishWorkspaceKind) -> String? {
        UserDefaults.standard.string(forKey: activeKey(kind: kind))
    }

    static func setActiveId(_ id: String?, kind: PublishWorkspaceKind) {
        UserDefaults.standard.set(id, forKey: activeKey(kind: kind))
    }

    static func upsert(_ snapshot: PublishWorkspaceSessionSnapshot, kind: PublishWorkspaceKind) {
        var list = list(kind: kind)
        if let idx = list.firstIndex(where: { $0.id == snapshot.id }) {
            list[idx] = snapshot
        } else {
            list.insert(snapshot, at: 0)
        }
        if list.count > maxSessions {
            list = Array(list.prefix(maxSessions))
        }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: storageKey(kind: kind))
        }
        setActiveId(snapshot.id, kind: kind)
    }

    static func delete(id: String, kind: PublishWorkspaceKind) -> String? {
        var list = list(kind: kind)
        list.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: storageKey(kind: kind))
        }
        if activeId(kind: kind) == id {
            let next = list.first?.id
            setActiveId(next, kind: kind)
            return next
        }
        return activeId(kind: kind)
    }

    static func get(_ id: String, kind: PublishWorkspaceKind) -> PublishWorkspaceSessionSnapshot? {
        list(kind: kind).first { $0.id == id }
    }

    static func makeEmpty(kind: PublishWorkspaceKind) -> PublishWorkspaceSessionSnapshot {
        PublishWorkspaceSessionSnapshot(
            id: UUID().uuidString,
            title: kind == .service ? "新服务卡" : "新需求",
            updatedAt: Date().timeIntervalSince1970,
            messages: [],
            input: "",
            fields: PublishWorkspaceFieldsDTO(PublishWorkspaceFields()),
            fieldOverrides: [],
            lockedKeywords: [],
            missingInfo: [],
            missingQueue: PublishMissingQueueState(),
            confidence: "low",
            readyToPublish: false,
            speedMode: false
        )
    }

    static func deriveTitle(fields: PublishWorkspaceFields, messages: [PublishWorkspaceChatMessage]) -> String {
        let t = fields.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return String(t.prefix(48)) }
        if let first = messages.first(where: { $0.role == "user" })?.content.trimmingCharacters(in: .whitespacesAndNewlines),
           !first.isEmpty {
            return String(first.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).prefix(48))
        }
        return "未命名草稿"
    }
}
