import Foundation
import Observation

@MainActor
protocol DemandDiscovering {
    func discover(
        page: Int,
        limit: Int,
        keyword: String?,
        lat: Double?,
        lng: Double?,
        distanceKm: Double?
    ) async throws -> [Demand]
}

@Observable
@MainActor
final class DiscoverFeatureModel {
    private(set) var demands: [Demand] = []
    var selectedDemand: Demand?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let repository: (any DemandDiscovering)?
    private let previewDemands: [Demand]?

    init(repository: any DemandDiscovering) {
        self.repository = repository
        self.previewDemands = nil
    }

    init(previewDemands: [Demand]) {
        self.repository = nil
        self.previewDemands = previewDemands
    }

    func load(
        keyword: String? = nil,
        nearbyOnly: Bool = false
    ) async {
        guard !isLoading else { return }
        if let previewDemands {
            demands = previewDemands
            selectedDemand = selectedDemand.flatMap { selected in
                previewDemands.first(where: { $0.id == selected.id })
            } ?? previewDemands.first
            errorMessage = nil
            return
        }
        guard let repository else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // 无定位权限时附近用上海默认坐标；服务端 haversine + distance
            let lat: Double? = nearbyOnly ? 31.2304 : nil
            let lng: Double? = nearbyOnly ? 121.4737 : nil
            let rows = try await repository.discover(
                page: 1,
                limit: 20,
                keyword: keyword,
                lat: lat,
                lng: lng,
                distanceKm: nearbyOnly ? 20 : nil
            )
            demands = rows
            if let selectedID = selectedDemand?.id {
                selectedDemand = rows.first(where: { $0.id == selectedID }) ?? rows.first
            } else {
                selectedDemand = rows.first
            }
        } catch {
            demands = []
            selectedDemand = nil
            errorMessage = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
