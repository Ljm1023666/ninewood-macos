import SwiftUI

struct DiscoverView: View {
    @Environment(AppSession.self) private var session
    @State private var demands: [Demand] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var selectedDemand: Demand?

    var body: some View {
        NavigationStack {
            SplitListDetailShell(minListWidth: 360, idealListWidth: 420) {
                listPane
            } detail: {
                Group {
                    if let selectedDemand {
                        DemandDetailView(demand: selectedDemand)
                            .id(selectedDemand.id)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .trailing)).combined(with: .offset(x: 12)),
                                removal: .opacity
                            ))
                    } else {
                        NWDetailPlaceholder(
                            title: "选择需求",
                            systemImage: "doc.text.magnifyingglass",
                            message: "从左侧列表选择一条需求查看详情"
                        )
                        .transition(.opacity)
                    }
                }
                .animation(.spring(response: 0.36, dampingFraction: 0.9), value: selectedDemand?.id)
            }
            .navigationTitle("发现")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await loadDemands() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
        }
        .task { await loadDemands() }
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            NWPaneCaption(text: "附近需求")

            if let loadError {
                VStack(alignment: .leading, spacing: AppTheme.space8) {
                    Text(loadError)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("重新加载") { Task { await loadDemands() } }
                }
                .padding(AppTheme.space16)
                Spacer(minLength: 0)
            } else if demands.isEmpty && !isLoading {
                NWEmptyState(title: "暂无需求", systemImage: "tray", message: "稍后再来看看附近有什么新需求")
                Spacer(minLength: 0)
            } else {
                List(demands, selection: $selectedDemand) { demand in
                    DemandRowView(demand: demand)
                        .tag(demand)
                        .listRowInsets(EdgeInsets(
                            top: 10,
                            leading: AppTheme.space16,
                            bottom: 10,
                            trailing: AppTheme.space16
                        ))
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .overlay(alignment: .topTrailing) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(AppTheme.space16)
                    }
                }
            }
        }
    }

    private func loadDemands() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            demands = try await session.demandService.searchDemands()
            if selectedDemand == nil {
                selectedDemand = demands.first
            }
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            demands = []
        }
    }
}

struct DemandRowView: View {
    let demand: Demand

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.space8) {
                Text(demand.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(demand.minPrice.currencyText)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .layoutPriority(1)
            }

            if let subtitle = demand.listSubtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: AppTheme.space12) {
                Label(demand.distanceText, systemImage: "location")
                Label("\(demand.applicantCount)/\(demand.applicantLimit)", systemImage: "person.2")
                if demand.state == .urgent {
                    NWStatusChip(text: "急", tint: AppTheme.urgent)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
