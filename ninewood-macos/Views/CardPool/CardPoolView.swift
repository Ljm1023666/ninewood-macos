import SwiftUI

struct CardPoolView: View {
    @Environment(AppSession.self) private var session
    @State private var poolTab: PoolTab = .active
    @State private var demands: [Demand] = []
    @State private var selectedDemand: Demand?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showMyServiceCards = false

    private enum PoolTab: String, CaseIterable, Identifiable {
        case active = "进行中"
        case dead = "死池"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                listPane
                    .paneColumn(minWidth: 360, idealWidth: 420)
                Divider()
                Group {
                    if let selectedDemand {
                        DemandDetailView(
                            demand: selectedDemand,
                            poolMode: poolTab == .dead ? .deadPool : .activePool
                        )
                        .id(selectedDemand.id)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)).combined(with: .offset(x: 12)),
                            removal: .opacity
                        ))
                    } else {
                        NWDetailPlaceholder(
                            title: "选择需求",
                            systemImage: "square.stack.3d.up",
                            message: "从左侧卡池选择一条需求查看详情"
                        )
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.spring(response: 0.36, dampingFraction: 0.9), value: selectedDemand?.id)
            }
            .navigationTitle("卡池")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("我的服务卡") { showMyServiceCards = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await load() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .sheet(isPresented: $showMyServiceCards) {
                NavigationStack {
                    MyServiceCardsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") { showMyServiceCards = false }
                            }
                        }
                }
                .frame(minWidth: 520, minHeight: 420)
            }
        }
        .task { await load() }
        .onChange(of: poolTab) { _, _ in
            selectedDemand = nil
            Task { await load() }
        }
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("卡池", selection: $poolTab) {
                ForEach(PoolTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AppTheme.space16)
            .padding(.top, AppTheme.space12)
            .padding(.bottom, AppTheme.space8)

            NWPaneCaption(text: poolTab == .active ? "进行中的公开需求" : "过期 / 死池需求（可抢单）")

            if let loadError {
                VStack(alignment: .leading, spacing: AppTheme.space8) {
                    Text(loadError).foregroundStyle(.secondary)
                    Button("重新加载") { Task { await load() } }
                }
                .padding(AppTheme.space16)
                Spacer(minLength: 0)
            } else if isLoading && demands.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                Spacer(minLength: 0)
            } else if demands.isEmpty {
                NWEmptyState(
                    title: poolTab == .active ? "暂无进行中的需求" : "死池暂无需求",
                    systemImage: "tray",
                    message: poolTab == .active
                        ? "卡池会汇总可竞价 / 可接的公开需求"
                        : "过期未成交的需求会进入死池，可尝试抢单"
                )
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
            }
        }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            demands = switch poolTab {
            case .active:
                try await session.demandService.poolActive()
            case .dead:
                try await session.demandService.poolDead()
            }
            if let selectedDemand, demands.contains(where: { $0.id == selectedDemand.id }) {
                // keep
            } else {
                self.selectedDemand = demands.first
            }
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            demands = []
        }
    }
}

private struct MyServiceCardsView: View {
    @Environment(AppSession.self) private var session
    @State private var cards: [ServiceCardDTO] = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        Group {
            if let loadError {
                NWEmptyState(title: "加载失败", systemImage: "exclamationmark.triangle", message: loadError)
            } else if isLoading && cards.isEmpty {
                ProgressView()
            } else if cards.isEmpty {
                NWEmptyState(title: "暂无服务卡", systemImage: "rectangle.stack", message: "发布服务卡后会出现在这里")
            } else {
                List(cards) { card in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(card.title).font(.headline)
                        if let summary = card.summary ?? card.description {
                            Text(summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        HStack {
                            if let category = card.category {
                                Text(category).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let status = card.status {
                                NWStatusChip(text: status)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.workspaceBackground)
        .navigationTitle("我的服务卡")
        .task { await load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("刷新") { Task { await load() } }
            }
        }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            cards = try await session.serviceCardService.mine()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
