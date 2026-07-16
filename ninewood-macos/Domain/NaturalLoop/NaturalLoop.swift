import Foundation

/// HUMAN/EARTH/HEAVEN describe the current outer boundary, not separate products.
enum NaturalLoopBoundaryKind: String, Codable, CaseIterable, Hashable, Sendable {
    case human = "HUMAN"
    case earth = "EARTH"
    case heaven = "HEAVEN"
}

enum NaturalLoopStage: Hashable, Sendable {
    case triggered
    case matching
    case executing
    case waitingHuman
    case verifying
    case succeeded
    case failed
    case inconclusive
    case closed
    case unknown(String)

    init(backendValue: String) {
        let normalized = backendValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch normalized {
        case "TRIGGERED": self = .triggered
        case "MATCHING": self = .matching
        case "EXECUTING": self = .executing
        case "WAITING_HUMAN": self = .waitingHuman
        case "VERIFYING": self = .verifying
        case "SUCCEEDED": self = .succeeded
        case "FAILED": self = .failed
        case "INCONCLUSIVE": self = .inconclusive
        case "CLOSED": self = .closed
        default: self = .unknown(normalized.isEmpty ? backendValue : normalized)
        }
    }

    var backendValue: String {
        switch self {
        case .triggered: "TRIGGERED"
        case .matching: "MATCHING"
        case .executing: "EXECUTING"
        case .waitingHuman: "WAITING_HUMAN"
        case .verifying: "VERIFYING"
        case .succeeded: "SUCCEEDED"
        case .failed: "FAILED"
        case .inconclusive: "INCONCLUSIVE"
        case .closed: "CLOSED"
        case let .unknown(value): value
        }
    }

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .inconclusive, .closed: true
        default: false
        }
    }
}

indirect enum LoopValue: Hashable, Sendable {
    case object([String: LoopValue])
    case array([LoopValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
}

struct NaturalLoopDefinition: Hashable, Sendable {
    let code: String
    let name: String
    let description: String?
    let executionMode: String?
}

struct NaturalLoop: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let summary: String?
    let boundaryKind: NaturalLoopBoundaryKind
    let definition: NaturalLoopDefinition?
    let paths: [String]
    let requiresVerification: Bool
}

struct NaturalLoopOffering: Identifiable, Hashable, Sendable {
    let id: String
    let loop: NaturalLoop
    let executionMode: String?
}

struct NaturalLoopRecommendation: Identifiable, Hashable, Sendable {
    var id: String { offering.id }
    let offering: NaturalLoopOffering
}

struct NaturalLoopRecommendations: Hashable, Sendable {
    let query: String?
    let items: [NaturalLoopRecommendation]
    /// A local draft only. Publishing remains an explicit Demand-flow action.
    let humanFallback: HumanFallbackDraft?
}

struct HumanFallbackDraft: Hashable, Sendable {
    let title: String
    let description: String?
    let paths: [String]
    let requiresConfirmation: Bool
}

struct LoopContext: Hashable, Sendable {
    let initiatorReference: String?
    let receiverReference: String?
    let demandID: String?
    let orderID: String?
    let parentRunID: String?
    let correlationID: String?
    let input: LoopValue?
    let expectedOutcome: LoopValue?
    let actualOutcome: LoopValue?
}

struct LoopEvidence: Identifiable, Hashable, Sendable {
    let id: String
    let type: String
    let actorReference: String?
    let visibility: String?
    let payload: LoopValue?
    let createdAt: Date?
}

struct LoopIntervention: Identifiable, Hashable, Sendable {
    let id: String
    let status: String
    let result: LoopValue?
    let verifierID: String?
    let verifierCode: String?
    let verifierName: String?
    let createdAt: Date?
}

struct NaturalLoopLink: Identifiable, Hashable, Sendable {
    let id: String
    let relation: String
    let direction: Direction
    let linkedRunID: String
    let linkedRunStage: NaturalLoopStage
    let linkedDefinition: NaturalLoopDefinition?

    enum Direction: Hashable, Sendable {
        case incoming
        case outgoing
    }
}

struct NaturalLoopRun: Identifiable, Hashable, Sendable {
    let id: String
    let boundaryKind: NaturalLoopBoundaryKind
    let stage: NaturalLoopStage
    let progress: Double?
    let definition: NaturalLoopDefinition?
    let offering: NaturalLoopOffering?
    let context: LoopContext
    let evidence: [LoopEvidence]
    let interventions: [LoopIntervention]
    let links: [NaturalLoopLink]
    let startedAt: Date?
    let completedAt: Date?
    let createdAt: Date?
}

struct NaturalLoopRunSummary: Hashable, Sendable {
    let total: Int
    let active: Int
    let succeeded: Int
    let failed: Int
    let successRate: Double?
}

struct NaturalLoopRunCollection: Hashable, Sendable {
    let runs: [NaturalLoopRun]
    let summary: NaturalLoopRunSummary?
}

struct NaturalLoopExecution: Hashable, Sendable {
    let runID: String?
    let didRun: Bool
    let isPreview: Bool
    let definitionCode: String?
    let stage: NaturalLoopStage
    let outcome: LoopValue?
    let run: NaturalLoopRun?
}
