import SwiftUI

/// 我的需求：发布者管理申请 / 撤回
struct MyDemandsView: View {
    @Environment(AppSession.self) private var session
    @State private var demands: [Demand] = []
    @State private var selected: Demand?
    @State private var applicants: [DemandApplicant] = []
    @State private var bids: [DemandBidDTO] = []
    @State private var isLoading = false
    @State private var message: String?
    @State private var loadError: String?
    @State private var applicantsError: String?
    @State private var bidsError: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                NWPaneCaption(text: "管理发布与申请人")
                if isLoading && demands.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 32)
                    Spacer(minLength: 0)
                } else if let loadError, demands.isEmpty {
                    NWEmptyState(title: "需求加载失败", systemImage: "wifi.exclamationmark", message: loadError)
                    Spacer(minLength: 0)
                } else if demands.isEmpty {
                    NWEmptyState(title: "还没有发布需求", systemImage: "doc.badge.plus", message: "去「发布」创建第一条需求")
                    Spacer(minLength: 0)
                } else {
                    List(demands, selection: $selected) { demand in
                        DemandRowView(demand: demand)
                            .tag(demand)
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                }
            }
            .paneColumn(minWidth: 320, idealWidth: 380)

            Divider()

            Group {
                if let selected {
                    ownerDetail(selected)
                } else {
                    NWDetailPlaceholder(title: "选择需求", systemImage: "doc.text", message: "查看申请人并接受 / 拒绝")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("我的需求")
        .task { await load() }
        .toolbar { Button("刷新") { Task { await load() } } }
        .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("确定", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private func ownerDetail(_ demand: Demand) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(demand.title).font(.title2.bold())
                Text(demand.expectedOutcome).foregroundStyle(.secondary)
                HStack {
                    Button("撤回需求", role: .destructive) {
                        Task { await withdraw(demand.id) }
                    }
                    Spacer()
                    NavigationLink("打开详情") {
                        DemandDetailView(demand: demand)
                    }
                }

                Text("申请人").font(.headline)
                if let applicantsError, applicants.isEmpty {
                    NWEmptyState(title: "申请人加载失败", systemImage: "wifi.exclamationmark", message: applicantsError)
                } else if applicants.isEmpty {
                    Text("暂无申请").foregroundStyle(.secondary)
                } else {
                    ForEach(applicants) { applicant in
                        HStack(spacing: 12) {
                            NWAvatarView(
                                url: applicant.user.avatarMediaURL,
                                name: applicant.user.name,
                                size: 42
                            )
                            VStack(alignment: .leading) {
                                Text(applicant.user.name).font(.body.weight(.semibold))
                                Text(applicant.message).font(.caption).foregroundStyle(.secondary)
                                Text(applicant.status).font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if applicant.status.uppercased() == "PENDING" || applicant.status.uppercased() == "REQUESTED" {
                                Button("接受") { Task { await accept(demand.id, applicant.id) } }
                                    .buttonStyle(.borderedProminent)
                                Button("拒绝") { Task { await reject(demand.id, applicant.id) } }
                            }
                        }
                        .padding(12)
                        .ninewoodCard()
                    }
                }

                Text("应标").font(.headline).padding(.top, 8)
                if let bidsError, bids.isEmpty {
                    NWEmptyState(title: "应标加载失败", systemImage: "wifi.exclamationmark", message: bidsError)
                } else if bids.isEmpty {
                    Text("暂无应标").foregroundStyle(.secondary)
                } else {
                    ForEach(bids.indices, id: \.self) { index in
                        let bid = bids[index]
                        HStack(spacing: 12) {
                            NWAvatarView(
                                url: bid.user?.avatarMediaURL,
                                name: bid.user?.nickname ?? "用户",
                                size: 42
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                Text(bid.user?.nickname ?? "用户")
                                    .font(.body.weight(.semibold))
                                if let message = bid.message, !message.isEmpty {
                                    Text(message).font(.caption).foregroundStyle(.secondary)
                                }
                                HStack(spacing: 8) {
                                    if let price = bid.offerPrice?.value {
                                        Text("报价 \(price.currencyText)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let status = bid.status {
                                        Text(status).font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            Spacer()
                        }
                        .padding(12)
                        .ninewoodCard()
                    }
                }
            }
            .padding(AppTheme.horizontalPadding)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .background(AppTheme.workspaceBackground)
        .task(id: demand.id) {
            await loadApplicants(demand.id)
            await loadBids(demand.id)
        }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            demands = try await session.demandService.myDemands()
            if selected == nil { selected = demands.first }
        } catch {
            demands = []
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadApplicants(_ id: String) async {
        applicantsError = nil
        do {
            applicants = try await session.demandService.applicants(demandId: id)
        } catch {
            applicants = []
            applicantsError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadBids(_ id: String) async {
        bidsError = nil
        do {
            bids = try await session.demandService.bids(id: id)
        } catch {
            bids = []
            bidsError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func withdraw(_ id: String) async {
        do {
            try await session.demandService.withdraw(id: id)
            message = "已撤回"
            await load()
        } catch {
            message = error.localizedDescription
        }
    }

    private func accept(_ demandId: String, _ applicantId: String) async {
        do {
            _ = try await session.demandService.acceptApplicant(
                demandId: demandId,
                applicantId: applicantId,
                idempotencyKey: UUID().uuidString
            )
            message = "已接受，订单将生成"
            await loadApplicants(demandId)
        } catch {
            message = error.localizedDescription
        }
    }

    private func reject(_ demandId: String, _ applicantId: String) async {
        do {
            try await session.demandService.rejectApplicant(
                demandId: demandId,
                applicantId: applicantId,
                idempotencyKey: UUID().uuidString
            )
            message = "已拒绝"
            await loadApplicants(demandId)
        } catch {
            message = error.localizedDescription
        }
    }
}

struct MyBidsView: View {
    @Environment(AppSession.self) private var session
    @State private var items: [Demand] = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NWPaneCaption(text: "卡池应标与申请记录")
            if isLoading && items.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                Spacer()
            } else if let loadError, items.isEmpty {
                NWEmptyState(title: "应标加载失败", systemImage: "wifi.exclamationmark", message: loadError)
                Spacer()
            } else if items.isEmpty {
                NWEmptyState(title: "暂无应标", systemImage: "hand.raised", message: "在卡池或需求详情提交应标后会出现在这里")
                Spacer()
            } else {
                List(items) { demand in
                    NavigationLink {
                        DemandDetailView(demand: demand)
                    } label: {
                        DemandRowView(demand: demand)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.workspaceBackground)
        .navigationTitle("我的应标")
        .task { await load() }
        .toolbar { Button("刷新") { Task { await load() } } }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            items = try await session.demandService.myApplications()
        } catch {
            items = []
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
