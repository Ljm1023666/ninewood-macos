import Foundation

enum NaturalLoopMappingError: Error {
    case unsupportedBoundaryKind(String)
}

struct NaturalLoopMapper {
    func recommendations(from dto: LoopRecommendationResultDTO) throws -> NaturalLoopRecommendations {
        NaturalLoopRecommendations(
            query: dto.query,
            items: try dto.items.map { item in
                let loop = try NaturalLoop(
                    id: item.id,
                    title: item.title,
                    summary: item.summary,
                    boundaryKind: boundaryKind(item.loopKind),
                    definition: definition(
                        code: item.definitionCode,
                        name: item.definitionName,
                        description: nil,
                        executionMode: item.executionMode
                    ),
                    paths: item.paths ?? [],
                    requiresVerification: item.requiresVerification ?? false
                )
                return NaturalLoopRecommendation(
                    offering: NaturalLoopOffering(
                        id: item.id,
                        loop: loop,
                        executionMode: item.executionMode
                    )
                )
            },
            humanFallback: dto.humanFallback.map {
                HumanFallbackDraft(
                    title: $0.title ?? "发布一个人回",
                    description: $0.description,
                    paths: $0.paths ?? [],
                    requiresConfirmation: $0.requiresConfirmation ?? true
                )
            }
        )
    }

    func offering(from dto: LoopOfferingItemDTO) throws -> NaturalLoopOffering {
        let loop = try NaturalLoop(
            id: dto.id,
            title: dto.title,
            summary: dto.summary,
            boundaryKind: boundaryKind(dto.loopKind),
            definition: definition(
                code: dto.definitionCode,
                name: dto.definitionName,
                description: dto.definitionDescription,
                executionMode: nil
            ),
            paths: dto.paths ?? [],
            requiresVerification: dto.requiresVerification ?? false
        )
        return NaturalLoopOffering(id: dto.id, loop: loop, executionMode: nil)
    }

    func run(from dto: LoopRunDetailDTO) throws -> NaturalLoopRun {
        let boundary = try boundaryKind(dto.loopKind)
        let mappedDefinition = definition(from: dto.definition)
        let mappedOffering = dto.offering.map {
            offering(from: $0, boundary: boundary, definition: mappedDefinition)
        }
        return NaturalLoopRun(
            id: dto.id,
            boundaryKind: boundary,
            stage: NaturalLoopStage(backendValue: dto.status),
            progress: nil,
            definition: mappedDefinition,
            offering: mappedOffering,
            context: LoopContext(
                initiatorReference: dto.initiatorRef,
                receiverReference: dto.receiverRef,
                demandID: dto.demandId,
                orderID: dto.orderId,
                parentRunID: dto.parentRunId,
                correlationID: dto.correlationId,
                input: dto.inputJson.map(value),
                expectedOutcome: dto.expectedOutcome.map(value),
                actualOutcome: dto.actualOutcome.map(value)
            ),
            evidence: (dto.events ?? []).map(mapEvidence),
            interventions: (dto.verificationRuns ?? []).map(intervention),
            links: links(outgoing: dto.linksOut ?? [], incoming: dto.linksIn ?? []),
            startedAt: date(dto.startedAt),
            completedAt: date(dto.completedAt),
            createdAt: date(dto.createdAt)
        )
    }

    func run(from dto: MyLoopItemDTO) throws -> NaturalLoopRun {
        let boundary = try boundaryKind(dto.kind)
        let mappedDefinition = definition(from: dto.definition)
        let mappedOffering = dto.offering.map {
            offering(from: $0, boundary: boundary, definition: mappedDefinition)
        }
        return NaturalLoopRun(
            id: dto.id,
            boundaryKind: boundary,
            stage: NaturalLoopStage(backendValue: dto.status),
            progress: dto.progress,
            definition: mappedDefinition,
            offering: mappedOffering,
            context: LoopContext(
                initiatorReference: dto.initiatorRef,
                receiverReference: dto.receiverRef,
                demandID: dto.demandId,
                orderID: dto.orderId,
                parentRunID: nil,
                correlationID: nil,
                input: nil,
                expectedOutcome: nil,
                actualOutcome: nil
            ),
            evidence: dto.latestEvent.map { [mapEvidence($0)] } ?? [],
            interventions: [],
            links: [],
            startedAt: date(dto.startedAt),
            completedAt: date(dto.completedAt),
            createdAt: date(dto.createdAt)
        )
    }

    func runCollection(from dto: MyLoopsResultDTO) throws -> NaturalLoopRunCollection {
        NaturalLoopRunCollection(
            runs: try dto.items.map(run),
            summary: dto.summary.map {
                NaturalLoopRunSummary(
                    total: $0.total ?? dto.items.count,
                    active: $0.active ?? 0,
                    succeeded: $0.succeeded ?? 0,
                    failed: $0.failed ?? 0,
                    successRate: $0.successRate
                )
            }
        )
    }

    func evidence(from dto: LoopEventDTO) -> LoopEvidence {
        mapEvidence(dto)
    }

    func execution(
        from dto: LoopRunOfferingResultDTO,
        hydratedRun: NaturalLoopRun?
    ) -> NaturalLoopExecution {
        NaturalLoopExecution(
            runID: dto.runId,
            didRun: dto.ran ?? false,
            isPreview: dto.preview ?? false,
            definitionCode: dto.code,
            stage: NaturalLoopStage(backendValue: dto.status ?? "UNKNOWN"),
            outcome: dto.outcome.map(value),
            run: hydratedRun
        )
    }

    private func boundaryKind(_ rawValue: String) throws -> NaturalLoopBoundaryKind {
        guard let kind = NaturalLoopBoundaryKind(rawValue: rawValue.uppercased()) else {
            throw NaturalLoopMappingError.unsupportedBoundaryKind(rawValue)
        }
        return kind
    }

    private func definition(from dto: LoopDefinitionDTO?) -> NaturalLoopDefinition? {
        guard let dto else { return nil }
        return definition(
            code: dto.code,
            name: dto.name,
            description: dto.description,
            executionMode: dto.executionMode
        )
    }

    private func definition(
        code: String?,
        name: String?,
        description: String?,
        executionMode: String?
    ) -> NaturalLoopDefinition? {
        guard let code, let name else { return nil }
        return NaturalLoopDefinition(
            code: code,
            name: name,
            description: description,
            executionMode: executionMode
        )
    }

    private func offering(
        from dto: LoopOfferingBriefDTO,
        boundary: NaturalLoopBoundaryKind,
        definition: NaturalLoopDefinition?
    ) -> NaturalLoopOffering {
        let loop = NaturalLoop(
            id: dto.id,
            title: dto.title ?? definition?.name ?? "自然回",
            summary: dto.summary,
            boundaryKind: boundary,
            definition: definition,
            paths: [],
            requiresVerification: false
        )
        return NaturalLoopOffering(id: dto.id, loop: loop, executionMode: definition?.executionMode)
    }

    private func mapEvidence(_ dto: LoopEventDTO) -> LoopEvidence {
        let fallbackID = "\(dto.type):\(dto.createdAt ?? "")"
        return LoopEvidence(
            id: dto.id ?? fallbackID,
            type: dto.type,
            actorReference: dto.actorRef,
            visibility: dto.visibility,
            payload: dto.payload.map(value),
            createdAt: date(dto.createdAt)
        )
    }

    private func intervention(_ dto: LoopVerificationRunDTO) -> LoopIntervention {
        LoopIntervention(
            id: dto.id,
            status: dto.status,
            result: dto.resultJson.map(value),
            verifierID: dto.verifier?.id,
            verifierCode: dto.verifier?.code,
            verifierName: dto.verifier?.name,
            createdAt: date(dto.createdAt)
        )
    }

    private func links(outgoing: [LoopLinkDTO], incoming: [LoopLinkDTO]) -> [NaturalLoopLink] {
        let mappedOutgoing = outgoing.compactMap { link -> NaturalLoopLink? in
            guard let run = link.targetRun else { return nil }
            return NaturalLoopLink(
                id: link.id,
                relation: link.relation,
                direction: .outgoing,
                linkedRunID: run.id,
                linkedRunStage: NaturalLoopStage(backendValue: run.status),
                linkedDefinition: definition(from: run.definition)
            )
        }
        let mappedIncoming = incoming.compactMap { link -> NaturalLoopLink? in
            guard let run = link.sourceRun else { return nil }
            return NaturalLoopLink(
                id: link.id,
                relation: link.relation,
                direction: .incoming,
                linkedRunID: run.id,
                linkedRunStage: NaturalLoopStage(backendValue: run.status),
                linkedDefinition: definition(from: run.definition)
            )
        }
        return mappedOutgoing + mappedIncoming
    }

    private func value(_ dto: LoopJSONValue) -> LoopValue {
        switch dto {
        case let .object(object):
            return .object(object.mapValues(value))
        case let .array(array):
            return .array(array.map(value))
        case let .string(string):
            return .string(string)
        case let .number(number):
            return .number(number)
        case let .bool(bool):
            return .bool(bool)
        case .null:
            return .null
        }
    }

    private func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}
