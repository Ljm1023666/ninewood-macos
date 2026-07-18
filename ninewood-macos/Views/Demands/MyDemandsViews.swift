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
    @State private var demandToDelete: Demand?
    @State private var statusFilter: DemandStatusFilter = .all
    private let previewDemands: [Demand]?
    private let previewApplicants: [DemandApplicant]

    private enum DemandStatusFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case active = "公开中"
        case inProgress = "沟通中"
        case frozen = "已冻结"
        var id: String { rawValue }
    }

    init(
        previewDemands: [Demand]? = nil,
        previewApplicants: [DemandApplicant] = []
    ) {
        self.previewDemands = previewDemands
        self.previewApplicants = previewApplicants
        _demands = State(initialValue: previewDemands ?? [])
        _selected = State(initialValue: previewDemands?.first)
        _applicants = State(initialValue: previewApplicants)
    }

    private var filteredDemands: [Demand] {
        guard previewDemands != nil else { return demands }
        switch statusFilter {
        case .all: return demands
        case .active: return demands.filter { $0.status == .active }
        case .inProgress: return demands.filter { $0.status == .inProgress }
        case .frozen: return demands.filter { $0.status == .frozen }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if previewDemands != nil {
                    HStack {
                        Spacer()
                        Button {} label: {
                            Label("发布新需求", systemImage: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .background(AppTheme.primary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                    HStack(spacing: 16) {
                        ForEach(DemandStatusFilter.allCases) { tab in
                            let selected = statusFilter == tab
                            Button {
                                statusFilter = tab
                            } label: {
                                VStack(spacing: 6) {
                                    Text(tab.rawValue)
                                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                                        .foregroundStyle(selected ? AppTheme.primary : .secondary)
                                    Rectangle()
                                        .fill(selected ? AppTheme.primary : Color.clear)
                                        .frame(height: 2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                } else {
                    NWPaneCaption(text: "管理发布与申请人")
                }
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
                    List(filteredDemands, selection: $selected) { demand in
                        DemandRowView(demand: demand, isSelected: selected?.id == demand.id)
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
                    if previewDemands != nil {
                        MyDemandsDesignReferenceDetail(
                            demand: selected,
                            applicants: applicants
                        )
                    } else {
                        ownerDetail(selected)
                    }
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
        .confirmationDialog(
            "永久删除冻结需求？",
            isPresented: Binding(
                get: { demandToDelete != nil },
                set: { if !$0 { demandToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("永久删除并按规则退回托管", role: .destructive) {
                guard let id = demandToDelete?.id else { return }
                demandToDelete = nil
                Task { await deleteDemand(id) }
            }
            Button("取消", role: .cancel) {
                demandToDelete = nil
            }
        } message: {
            Text("该操作不可撤销。服务端仅允许删除冻结需求，并按冻结删除规则处理托管退款。")
        }
    }

    private func ownerDetail(_ demand: Demand) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(demand.title).font(.title2.bold())
                Text(demand.expectedOutcome).foregroundStyle(.secondary)
                HStack {
                    if demand.status == .frozen {
                        Button("永久删除", role: .destructive) {
                            demandToDelete = demand
                        }
                    } else if demand.status == .active {
                        Button("撤回需求", role: .destructive) {
                            Task { await withdraw(demand.id) }
                        }
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

                Text("应标（意向报价，不可直接成单）").font(.headline).padding(.top, 8)
                Text("正式接单请在上方「申请人」中接受；应标列表仅供参考，客户端不提供 accept-bid。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        if let previewDemands {
            demands = previewDemands
            selected = selected ?? previewDemands.first
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            demands = try await session.demandRepository.mine()
            if selected == nil { selected = demands.first }
        } catch {
            demands = []
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadApplicants(_ id: String) async {
        if previewDemands != nil {
            applicants = previewApplicants
            return
        }
        applicantsError = nil
        do {
            applicants = try await session.demandRepository.applicants(demandID: id)
        } catch {
            applicants = []
            applicantsError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadBids(_ id: String) async {
        if previewDemands != nil {
            bids = []
            bidsError = nil
            return
        }
        bidsError = nil
        do {
            bids = try await session.demandRepository.bids(demandID: id)
        } catch {
            bids = []
            bidsError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func withdraw(_ id: String) async {
        do {
            try await session.demandRepository.withdraw(id: id)
            message = "已撤回"
            await load()
        } catch {
            message = error.localizedDescription
        }
    }

    private func deleteDemand(_ id: String) async {
        do {
            try await session.demandRepository.delete(id: id)
            selected = nil
            message = "需求已删除，托管退款以钱包流水为准"
            await load()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func accept(_ demandId: String, _ applicantId: String) async {
        do {
            _ = try await session.demandRepository.accept(
                demandID: demandId,
                applicantID: applicantId,
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
            try await session.demandRepository.reject(
                demandID: demandId,
                applicantID: applicantId,
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
    @State private var selected: Demand?
    @State private var bidStatusFilter: BidStatusFilter = .all
    @State private var actionMessage: String?
    private let previewItems: [Demand]?

    private enum BidStatusFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case pending = "待处理"
        case accepted = "已接受"
        case rejected = "已拒绝"
        var id: String { rawValue }
    }

    init(previewItems: [Demand]? = nil) {
        self.previewItems = previewItems
        _items = State(initialValue: previewItems ?? [])
        _selected = State(initialValue: previewItems?.first)
    }

    private var filteredItems: [Demand] {
        guard previewItems != nil else { return items }
        switch bidStatusFilter {
        case .all: return items
        case .pending: return Array(items.prefix(2))
        case .accepted: return Array(items.dropFirst().prefix(1))
        case .rejected: return Array(items.dropFirst(2))
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if previewItems != nil {
                    HStack(spacing: 16) {
                        ForEach(BidStatusFilter.allCases) { tab in
                            let selectedTab = bidStatusFilter == tab
                            Button { bidStatusFilter = tab } label: {
                                HStack(spacing: 4) {
                                    if tab == .pending {
                                        Circle().fill(AppTheme.urgent).frame(width: 6, height: 6)
                                    } else if tab == .accepted {
                                        Circle().fill(AppTheme.openStatus).frame(width: 6, height: 6)
                                    } else if tab == .rejected {
                                        Circle().fill(AppTheme.secondaryLabel).frame(width: 6, height: 6)
                                    }
                                    Text(tab.rawValue)
                                        .font(.system(size: 13, weight: selectedTab ? .semibold : .regular))
                                        .foregroundStyle(selectedTab ? AppTheme.primary : .secondary)
                                }
                                .overlay(alignment: .bottom) {
                                    Rectangle()
                                        .fill(selectedTab ? AppTheme.primary : Color.clear)
                                        .frame(height: 2)
                                        .offset(y: 8)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 8)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 4)
                } else {
                    NWPaneCaption(text: "卡池应标与申请记录")
                }
                if isLoading && items.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    Spacer()
                } else if let loadError, items.isEmpty {
                    NWEmptyState(title: "应标加载失败", systemImage: "wifi.exclamationmark", message: loadError)
                    Spacer()
                } else if items.isEmpty {
                    NWEmptyState(title: "暂无应标", systemImage: "hand.raised", message: "在卡池或需求详情提交应标后会出现在这里")
                    Spacer()
                } else if previewItems != nil {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(filteredItems) { demand in
                                previewBidCard(demand)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    }
                    Text("共 12 条应标记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(16)
                    Spacer(minLength: 0)
                } else {
                    List(items, selection: $selected) { demand in
                        DemandRowView(demand: demand)
                            .tag(demand)
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                }
            }
            .paneColumn(minWidth: 320, idealWidth: 380)
            Divider()
            if let selected {
                if previewItems != nil {
                    MyBidsDesignReferenceDetail(demand: selected)
                } else {
                    MyBidsLiveDetail(
                        demand: selected,
                        onWithdraw: {
                            Task { await withdrawBid(selected) }
                        }
                    )
                    .nwStableDetailIdentity(selected.id)
                }
            } else {
                NWDetailPlaceholder(title: "选择应标记录", systemImage: "hand.raised", message: "查看需求与当前申请状态")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.workspaceBackground)
        .navigationTitle("我的应标")
        .task { await load() }
        .toolbar { Button("刷新") { Task { await load() } } }
        .alert("应标", isPresented: Binding(
            get: { actionMessage != nil },
            set: { if !$0 { actionMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(actionMessage ?? "")
        }
    }

    private func previewBidCard(_ demand: Demand) -> some View {
        let isSelected = selected?.id == demand.id
        return Button {
            selected = demand
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(demand.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                    Spacer()
                    NWStatusChip(text: "待处理", tint: AppTheme.urgent)
                }
                Text(demand.tags.first ?? "视觉设计")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(demand.minPrice.pointsText)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("提交于 2025/05/21 16:40")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? AppTheme.primary : AppTheme.outlineVariant, lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        if let previewItems {
            items = previewItems
            selected = selected ?? previewItems.first
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            items = try await session.demandRepository.myApplications()
            if let selected, !items.contains(where: { $0.id == selected.id }) {
                self.selected = items.first
            } else if self.selected == nil {
                self.selected = items.first
            }
        } catch {
            items = []
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func withdrawBid(_ demand: Demand) async {
        guard let applicationId = demand.applicationId, !applicationId.isEmpty else {
            actionMessage = "缺少申请 ID，无法撤回"
            return
        }
        do {
            try await session.demandService.withdrawBid(applicationId: applicationId)
            actionMessage = "已撤回应标"
            await load()
        } catch {
            actionMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct MyBidsLiveDetail: View {
    let demand: Demand
    var onWithdraw: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(demand.title)
                    .font(.headline)
                    .lineLimit(1)
                NWStatusChip(text: demand.status.title, tint: AppTheme.urgent)
                Spacer()
                Button("撤回应标", action: onWithdraw)
                    .buttonStyle(.bordered)
                    .disabled(demand.applicationId == nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            DemandDetailView(demand: demand, previewMode: false)
        }
    }
}

enum DemandManagementPreviewFixtures {
    static let applicants: [DemandApplicant] = [
        DemandApplicant(
            id: "preview-applicant-1",
            user: OrdersDesignPreviewFixtures.provider,
            message: "我有相同类型项目经验，可以先同步一次交付范围。",
            status: "PENDING",
            createdAt: Date(),
            communicationDeadline: Date().addingTimeInterval(45 * 60)
        ),
        DemandApplicant(
            id: "preview-applicant-2",
            user: AppUser(
                id: "preview-applicant-user-2",
                name: "周柠檬",
                avatarUrl: nil,
                coverUrl: nil,
                demandCardCoverUrl: nil,
                creditScore: 88,
                completedOrders: 31,
                goodRate: 0.97
            ),
            message: "可在三天内完成初稿，并提供一次集中修改。",
            status: "COMMUNICATING",
            createdAt: Date().addingTimeInterval(-3600),
            communicationDeadline: Date().addingTimeInterval(30 * 60)
        )
    ]
}

// MARK: - Design reference panes (14 / 22)

private struct MyDemandsDesignReferenceDetail: View {
    let demand: Demand
    let applicants: [DemandApplicant]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(demand.title).font(.title2.bold())
                    NWStatusChip(text: "沟通中", tint: AppTheme.primary)
                    Spacer()
                    Button("撤回需求") {}
                        .buttonStyle(.bordered)
                    Button("删除需求", role: .destructive) {}
                        .buttonStyle(.bordered)
                }
                Text(demand.expectedOutcome)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    infoTile("预算", value: "¥15,000", detail: "托管金额：¥15,000")
                    infoTile("预期成果", value: "完整报告", detail: "用户研究报告")
                    infoTile("申请进度", value: "8 位申请人", detail: "3 位已沟通")
                    infoTile("沟通时间", value: "2025/06/01 - 06/15", detail: "剩余 9 天")
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("附件（2）").font(.headline)
                        Spacer()
                        Button("全部下载") {}
                            .font(.caption)
                            .foregroundStyle(AppTheme.primary)
                    }
                    HStack(spacing: 10) {
                        attachmentChip("背景资料.pdf", symbol: "doc.fill", tint: AppTheme.error)
                        attachmentChip("功能清单.png", symbol: "photo.fill", tint: AppTheme.primary)
                    }
                }
                .padding(16)
                .ninewoodCard()

                Text("申请人（8）").font(.headline)
                ForEach(applicants) { applicant in
                    HStack(spacing: 12) {
                        NWAvatarView(url: applicant.user.avatarMediaURL, name: applicant.user.name, size: 42)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(applicant.user.name).font(.body.weight(.semibold))
                                NWStatusChip(text: "已认证", tint: AppTheme.openStatus)
                                NWStatusChip(text: "Lv.5", tint: AppTheme.secondaryLabel)
                            }
                            Text(applicant.message).font(.caption).foregroundStyle(.secondary)
                            Text("2 小时前").font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button("接受") {}
                            .buttonStyle(.borderedProminent)
                        Button("拒绝", role: .destructive) {}
                            .buttonStyle(.bordered)
                    }
                    .padding(12)
                    .ninewoodCard()
                }
                Button("查看全部 8 位申请人") {}
                    .font(.caption)
                    .foregroundStyle(AppTheme.primary)
            }
            .padding(AppTheme.horizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppTheme.workspaceBackground)
    }

    private func infoTile(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceLow, in: RoundedRectangle(cornerRadius: 8))
    }

    private func attachmentChip(_ name: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(name).font(.caption)
        }
        .padding(10)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(AppTheme.outlineVariant) }
    }
}

private struct MyBidsDesignReferenceDetail: View {
    let demand: Demand

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("品牌视觉系统与应用图标")
                        .font(.title2.bold())
                    NWStatusChip(text: "待处理", tint: AppTheme.urgent)
                    Spacer()
                    Button("撤回应标") {}
                        .buttonStyle(.bordered)
                    NWPrimaryCTA(title: "打开需求", systemImage: "arrow.up.right")
                        .frame(width: 140)
                }

                sectionBox("原需求概览") {
                    Text("为新一代消费电子产品设计统一的品牌视觉系统，含应用图标与基础规范。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        infoTile("预算", "800–1,200 点")
                        infoTile("发布时间", "2025/05/20")
                        infoTile("需求类型", "视觉设计")
                        infoTile("发布者", "Acme 科技")
                    }
                }

                sectionBox("我的应标") {
                    Text("我提供的价格").font(.caption).foregroundStyle(.secondary)
                    Text("900 点").font(.title.bold())
                    Text("我的方案说明").font(.caption.weight(.semibold)).padding(.top, 8)
                    Text("提供 3 套方向探索 + 最终交付源文件与规范文档。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                sectionBox("流程与状态") {
                    HStack(alignment: .top) {
                        bidStep("已提交应标", done: true, current: false)
                        bidStep("等待申请者查看", done: false, current: true)
                        bidStep("申请者接受", done: false, current: false)
                        bidStep("订单生成", done: false, current: false)
                    }
                }

                HStack(spacing: 12) {
                    infoTile("沟通资格", "可发起沟通")
                    infoTile("当前状态", "待处理")
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(AppTheme.primary)
                    Text("申请者接受应标后，系统将自动生成正式订单并通知双方。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.softPrimary, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(AppTheme.horizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppTheme.workspaceBackground)
    }

    private func sectionBox<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .padding(16)
        .ninewoodCard()
    }

    private func infoTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bidStep(_ title: String, done: Bool, current: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .strokeBorder(current || done ? AppTheme.primary : AppTheme.outlineVariant, lineWidth: current ? 2 : 1)
                    .background(Circle().fill(done ? AppTheme.primary : Color.clear))
                    .frame(width: 20, height: 20)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            Text(title)
                .font(.system(size: 10))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}
