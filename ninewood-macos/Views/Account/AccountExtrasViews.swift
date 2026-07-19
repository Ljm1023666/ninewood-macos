import SwiftUI
import PhotosUI

/// 通知（渲染图 17）：列表—详情分栏；设计预览用 fixture，线上走 MessageService。
struct NotificationsView: View {
    /// 兼容旧调用签名；前端复刻模式下忽略外部数据与后端。
    private let previewItems: [NotificationDTO]?

    @Environment(AppSession.self) private var session
    @State private var items: [NotificationsDesignItem]
    @State private var selectedID: String
    @State private var actionMessage: String?
    @State private var isLoading = false
    @State private var loadError: String?

    init(previewItems: [NotificationDTO]? = nil) {
        self.previewItems = previewItems
        let seed = NotificationsDesignFixtures.items
        _items = State(initialValue: seed)
        _selectedID = State(initialValue: seed.first?.id ?? "")
    }

    private var isDesignPreview: Bool {
        if previewItems != nil { return true }
        let env = ProcessInfo.processInfo.environment["NINEWOOD_DESIGN_PREVIEW"]
        return env == "17-notifications" || env == "17" || env == "notifications"
    }

    private var selected: NotificationsDesignItem? {
        items.first(where: { $0.id == selectedID }) ?? items.first
    }

    private var unreadCount: Int {
        items.filter { !$0.isRead }.count
    }

    private var grouped: [(String, [NotificationsDesignItem])] {
        let order = ["今天", "昨天", "更早"]
        let dict = Dictionary(grouping: items, by: \.group)
        return order.compactMap { key in
            guard let rows = dict[key], !rows.isEmpty else { return nil }
            return (key, rows)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            listPane
                .paneColumn(minWidth: 320, idealWidth: 360)

            Divider()

            Group {
                if let selected {
                    NotificationsDetailPane(
                        item: selected,
                        onOpen: { openNotification(selected) },
                        onMarkRead: { markRead(selected.id) }
                    )
                    .nwStableDetailIdentity(selected.id)
                } else {
                    NWDetailPlaceholder(
                        title: "选择通知",
                        systemImage: "bell",
                        message: "从左侧列表查看详情"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("通知")
        .alert("通知", isPresented: Binding(
            get: { actionMessage != nil },
            set: { if !$0 { actionMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(actionMessage ?? "")
        }
        .task {
            guard !isDesignPreview else { return }
            await load()
        }
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(AppTheme.error, in: Capsule())
                }
                Spacer(minLength: 8)
                Button {
                    markAllRead()
                } label: {
                    Label("全部标为已读", systemImage: "checkmark.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.primary)
                }
                .buttonStyle(.plain)
                .disabled(unreadCount == 0)

                Button {
                    if isDesignPreview {
                        items = NotificationsDesignFixtures.items
                        selectedID = items.first?.id ?? selectedID
                    } else {
                        Task { await load() }
                    }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
                .buttonStyle(.plain)
                .disabled(!isDesignPreview && isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()

            if !isDesignPreview && isLoading && items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                Spacer(minLength: 0)
            } else if !isDesignPreview, let loadError, items.isEmpty {
                NWEmptyState(title: "通知加载失败", systemImage: "wifi.exclamationmark", message: loadError)
                Spacer(minLength: 0)
            } else if items.isEmpty {
                NWEmptyState(title: "暂无通知", systemImage: "bell", message: "系统与业务通知会显示在这里")
                Spacer(minLength: 0)
            } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(grouped, id: \.0) { group, rows in
                        Text(group)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .padding(.bottom, 6)

                        ForEach(rows) { item in
                            Button {
                                selectedID = item.id
                                if !item.isRead {
                                    markRead(item.id)
                                }
                            } label: {
                                NotificationsListRow(
                                    item: item,
                                    isSelected: item.id == selected?.id
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if group != grouped.last?.0 {
                            Divider()
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
            }
        }
    }

    private func markRead(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard !items[index].isRead else { return }
        items[index].isRead = true
        guard !isDesignPreview else { return }
        Task {
            do {
                try await session.messageService.markNotificationRead(id: id)
            } catch {
                items[index].isRead = false
                actionMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func markAllRead() {
        let unreadIDs = items.filter { !$0.isRead }.map(\.id)
        guard !unreadIDs.isEmpty else { return }
        for index in items.indices {
            items[index].isRead = true
        }
        guard !isDesignPreview else { return }
        Task {
            do {
                try await session.messageService.markAllNotificationsRead()
            } catch {
                for id in unreadIDs {
                    if let index = items.firstIndex(where: { $0.id == id }) {
                        items[index].isRead = false
                    }
                }
                actionMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func openNotification(_ item: NotificationsDesignItem) {
        if isDesignPreview {
            actionMessage = openMessage(for: item)
            return
        }
        switch item.actionKind {
        case .order:
            if let orderId = item.orderId, session.navigation.navigate(to: "/orders/\(orderId)") {
                return
            }
        case .demand:
            if let demandId = item.demandId, session.navigation.navigate(to: "/demands/\(demandId)") {
                return
            }
        case .path:
            if let path = item.path, session.navigation.navigate(to: path) {
                return
            }
        case .none:
            break
        }
        actionMessage = openMessage(for: item)
    }

    private func openMessage(for item: NotificationsDesignItem) -> String {
        switch item.actionKind {
        case .order: return "将打开关联订单「\(item.relatedTitle ?? item.subtitle)」"
        case .demand: return "将打开关联需求「\(item.relatedTitle ?? item.subtitle)」"
        case .path: return "将打开「\(item.actionLabel)」"
        case .none: return "此通知没有可跳转的业务对象"
        }
    }

    private func load() async {
        if isDesignPreview {
            items = NotificationsDesignFixtures.items
            selectedID = items.first?.id ?? selectedID
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let page = try await session.messageService.notifications()
            let mapped = page.rows.map(mapNotification)
            items = mapped
            if let selected = mapped.first(where: { $0.id == selectedID }) {
                selectedID = selected.id
            } else {
                selectedID = mapped.first?.id ?? ""
            }
        } catch {
            items = []
            selectedID = ""
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func mapNotification(_ dto: NotificationDTO) -> NotificationsDesignItem {
        let deepLink = dto.deepLink
        let actionKind: NotificationsDesignItem.ActionKind = switch deepLink {
        case .order: .order
        case .demand: .demand
        case .path: .path
        case .none: .none
        }
        let actionLabel: String = switch deepLink {
        case .order: "打开订单"
        case .demand: "查看需求"
        case .path: notificationPathActionLabel(dto.path)
        case .none: "查看"
        }
        let icon = notificationIcon(for: dto.type)
        let title = dto.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "通知"
        let content = dto.content?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let subtitle = content ?? title
        let body = content ?? title
        let orderId: String? = if case .order(let id) = deepLink { id } else { nil }
        let demandId: String? = if case .demand(let id) = deepLink { id } else { nil }
        let path: String? = if case .path(let value) = deepLink { value } else { nil }

        return NotificationsDesignItem(
            id: dto.id,
            group: notificationGroup(for: dto.createdAt),
            title: title,
            subtitle: subtitle,
            body: body,
            timeLabel: notificationTimeLabel(for: dto.createdAt),
            isRead: dto.isRead ?? false,
            icon: icon.symbol,
            iconTint: icon.tint,
            actionKind: actionKind,
            actionLabel: actionLabel,
            orderId: orderId,
            demandId: demandId,
            path: path,
            relatedTitle: relatedTitle(for: dto, deepLink: deepLink),
            relatedStatus: nil,
            relatedPrice: nil,
            relatedTime: nil,
            demanderName: nil,
            providerName: nil
        )
    }

    private func notificationGroup(for iso: String?) -> String {
        guard let date = APIDate.parse(iso) else { return "更早" }
        if Calendar.current.isDateInToday(date) { return "今天" }
        if Calendar.current.isDateInYesterday(date) { return "昨天" }
        return "更早"
    }

    private func notificationTimeLabel(for iso: String?) -> String {
        guard let date = APIDate.parse(iso) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }
        if Calendar.current.isDateInYesterday(date) {
            formatter.dateFormat = "HH:mm"
            return "昨天 \(formatter.string(from: date))"
        }
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    private func notificationIcon(for type: String?) -> (symbol: String, tint: Color) {
        let normalized = (type ?? "").uppercased()
        if normalized.contains("ORDER") {
            return ("clipboard.fill", AppTheme.primary)
        }
        if normalized.contains("DEMAND") || normalized.contains("BID") || normalized.contains("REQUEST") {
            return ("person.crop.circle.badge.checkmark", AppTheme.openStatus)
        }
        if normalized.contains("MESSAGE") || normalized.contains("CHAT") {
            return ("bubble.left.fill", AppTheme.primary)
        }
        if normalized.contains("CERT") {
            return ("checkmark.shield.fill", AppTheme.openStatus)
        }
        if normalized.contains("WELFARE") {
            return ("gift.fill", AppTheme.urgent)
        }
        return ("bell.fill", Color(red: 0.55, green: 0.40, blue: 0.85))
    }

    private func notificationPathActionLabel(_ path: String?) -> String {
        guard let path else { return "打开" }
        if path.hasPrefix("/orders") { return "打开订单" }
        if path.hasPrefix("/demands") { return "查看需求" }
        if path.hasPrefix("/messages") { return "打开消息" }
        if path.hasPrefix("/welfare") { return "打开福利" }
        if path.hasPrefix("/cert") { return "打开认证" }
        return "打开"
    }

    private func relatedTitle(for dto: NotificationDTO, deepLink: NotificationDeepLink) -> String? {
        switch deepLink {
        case .order, .demand:
            return dto.content?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? dto.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        case .path, .none:
            return nil
        }
    }
}

// MARK: - Notifications list / detail

private struct NotificationsListRow: View {
    let item: NotificationsDesignItem
    var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(item.isRead ? Color.clear : AppTheme.primary)
                .frame(width: 7, height: 7)
                .padding(.top, 14)

            Image(systemName: item.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(item.iconTint)
                .frame(width: 34, height: 34)
                .background(item.iconTint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.onSurface)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(item.timeLabel)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryLabel.opacity(0.85))
                .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .nwSelectionChrome(isSelected: isSelected, cornerRadius: 10)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(AppTheme.primary.opacity(0.35), lineWidth: 1)
            }
        }
        .padding(.horizontal, 8)
    }
}

private struct NotificationsDetailPane: View {
    let item: NotificationsDesignItem
    var onOpen: () -> Void
    var onMarkRead: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: item.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(item.iconTint)
                            .frame(width: 48, height: 48)
                            .background(item.iconTint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(item.title)
                                    .font(.system(size: 20, weight: .bold))
                                if !item.isRead {
                                    Circle()
                                        .fill(AppTheme.primary)
                                        .frame(width: 8, height: 8)
                                }
                            }
                            Text(item.timeLabel)
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.secondaryLabel)
                        }
                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("你好，")
                            .font(.system(size: 14))
                        Text(item.body)
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.onSurface.opacity(0.9))
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if item.relatedTitle != nil {
                        relatedOrderCard
                    }
                }
                .padding(28)
                .frame(maxWidth: 720, alignment: .leading)
            }

            Divider()

            HStack {
                if !item.isRead {
                    Button("标为已读", action: onMarkRead)
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button(action: onOpen) {
                    Text(item.actionLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 280)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(AppTheme.surface)
        }
        .background(AppTheme.workspaceBackground)
        .onAppear {
            if !item.isRead { onMarkRead() }
        }
    }

    @ViewBuilder
    private var relatedOrderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("关联服务订单")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryLabel)

            HStack(spacing: 8) {
                Text(item.relatedTitle ?? "")
                    .font(.system(size: 15, weight: .semibold))
                if let status = item.relatedStatus {
                    Text(status)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppTheme.softPrimary, in: Capsule())
                }
                Spacer(minLength: 0)
            }

            if let demander = item.demanderName, let provider = item.providerName {
                HStack(spacing: 0) {
                    partyChip(name: demander, role: "需求方")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .frame(maxWidth: .infinity)
                    VStack(spacing: 2) {
                        Text("订单")
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Text(item.relatedStatus ?? "进行中")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.primary)
                    }
                    .frame(maxWidth: .infinity)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .frame(maxWidth: .infinity)
                    partyChip(name: provider, role: "服务方")
                }
                .padding(.vertical, 4)
            }

            HStack(spacing: 0) {
                metaCell(title: "订单阶段", value: item.relatedStatus ?? "—")
                metaCell(title: "服务价格", value: item.relatedPrice ?? "—")
                metaCell(title: "订单时间", value: item.relatedTime ?? "—")
            }
        }
        .padding(16)
        .ninewoodCard()
    }

    private func partyChip(name: String, role: String) -> some View {
        VStack(spacing: 4) {
            Text(role)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.secondaryLabel)
            HStack(spacing: 4) {
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.primary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func metaCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryLabel)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Notifications design model

private struct NotificationsDesignItem: Identifiable, Hashable {
    let id: String
    let group: String
    let title: String
    let subtitle: String
    let body: String
    let timeLabel: String
    var isRead: Bool
    let icon: String
    let iconTint: Color
    let actionKind: ActionKind
    let actionLabel: String
    let orderId: String?
    let demandId: String?
    let path: String?
    let relatedTitle: String?
    let relatedStatus: String?
    let relatedPrice: String?
    let relatedTime: String?
    let demanderName: String?
    let providerName: String?

    enum ActionKind: Hashable {
        case order, demand, path, none
    }
}

private enum NotificationsDesignFixtures {
    static let items: [NotificationsDesignItem] = [
        NotificationsDesignItem(
            id: "preview-notice-1",
            group: "今天",
            title: "订单进入待验收",
            subtitle: "产品需求与用户反馈整理",
            body: "服务订单「产品需求与用户反馈整理」已提交交付，进入待验收阶段。请在约定截止时间前确认成果；如有问题可发起沟通或提交争议。",
            timeLabel: "12:48",
            isRead: false,
            icon: "clipboard.fill",
            iconTint: AppTheme.primary,
            actionKind: .order,
            actionLabel: "打开订单",
            orderId: "preview-order-02",
            demandId: nil,
            path: nil,
            relatedTitle: "产品需求与用户反馈整理",
            relatedStatus: "待验收",
            relatedPrice: "600 点",
            relatedTime: "2025-05-20 12:48",
            demanderName: "林夏",
            providerName: "你"
        ),
        NotificationsDesignItem(
            id: "preview-notice-2",
            group: "今天",
            title: "收到新的接单申请",
            subtitle: "周屿申请了品牌视觉设计交付",
            body: "周屿申请了「品牌视觉设计交付」。你可以进入沟通窗口查看对方说明，并决定是否同意接单。",
            timeLabel: "11:20",
            isRead: false,
            icon: "person.crop.circle.badge.checkmark",
            iconTint: AppTheme.openStatus,
            actionKind: .demand,
            actionLabel: "查看需求",
            orderId: nil,
            demandId: "preview-01",
            path: nil,
            relatedTitle: "品牌视觉设计交付",
            relatedStatus: "待确认",
            relatedPrice: nil,
            relatedTime: nil,
            demanderName: nil,
            providerName: nil
        ),
        NotificationsDesignItem(
            id: "preview-notice-3",
            group: "今天",
            title: "新的私信回复",
            subtitle: "程野回复了你的消息",
            body: "程野在「用户访谈记录整理」沟通中回复了你，可前往消息继续协作。",
            timeLabel: "10:05",
            isRead: false,
            icon: "bubble.left.fill",
            iconTint: AppTheme.primary,
            actionKind: .path,
            actionLabel: "打开消息",
            orderId: nil,
            demandId: nil,
            path: "/messages",
            relatedTitle: nil,
            relatedStatus: nil,
            relatedPrice: nil,
            relatedTime: nil,
            demanderName: nil,
            providerName: nil
        ),
        NotificationsDesignItem(
            id: "preview-notice-4",
            group: "昨天",
            title: "认证资料已更新",
            subtitle: "服务标签审核通过",
            body: "你的服务标签已经通过审核，认证资料已更新。可在认证中心查看最新状态。",
            timeLabel: "昨天 09:30",
            isRead: true,
            icon: "checkmark.shield.fill",
            iconTint: AppTheme.openStatus,
            actionKind: .path,
            actionLabel: "打开认证",
            orderId: nil,
            demandId: nil,
            path: "/cert-center",
            relatedTitle: nil,
            relatedStatus: nil,
            relatedPrice: nil,
            relatedTime: nil,
            demanderName: nil,
            providerName: nil
        ),
        NotificationsDesignItem(
            id: "preview-notice-5",
            group: "昨天",
            title: "福利任务可领取",
            subtitle: "社区无障碍体验检查",
            body: "有新的公益任务「社区无障碍体验检查」符合你的条件，完成可获得积分奖励。",
            timeLabel: "昨天 16:12",
            isRead: true,
            icon: "gift.fill",
            iconTint: AppTheme.urgent,
            actionKind: .path,
            actionLabel: "打开福利",
            orderId: nil,
            demandId: nil,
            path: "/welfare",
            relatedTitle: nil,
            relatedStatus: nil,
            relatedPrice: nil,
            relatedTime: nil,
            demanderName: nil,
            providerName: nil
        ),
        NotificationsDesignItem(
            id: "preview-notice-6",
            group: "更早",
            title: "系统提醒",
            subtitle: "请及时确认进行中的订单",
            body: "你有订单接近验收截止时间，建议尽快核对交付物并完成确认。",
            timeLabel: "7/15",
            isRead: true,
            icon: "bell.fill",
            iconTint: Color(red: 0.55, green: 0.40, blue: 0.85),
            actionKind: .none,
            actionLabel: "查看",
            orderId: nil,
            demandId: nil,
            path: nil,
            relatedTitle: nil,
            relatedStatus: nil,
            relatedPrice: nil,
            relatedTime: nil,
            demanderName: nil,
            providerName: nil
        )
    ]
}

enum AccountDesignPreviewFixtures {
    static let users: [SoftUserDTO] = [
        SoftUserDTO(id: "preview-user-1", phone: nil, nickname: "周屿", avatarUrl: nil, coverUrl: nil, demandCardCoverUrl: nil, creditScore: 92, certificationLevel: "PRO", completedOrders: 46, bio: "产品与品牌视觉设计，重视过程透明与可靠交付。", cityCode: "310000", ipRegion: "上海", isFollowing: true, serviceTags: ["品牌视觉", "图标设计"], tags: nil),
        SoftUserDTO(id: "preview-user-2", phone: nil, nickname: "程野", avatarUrl: nil, coverUrl: nil, demandCardCoverUrl: nil, creditScore: 88, certificationLevel: "VERIFIED", completedOrders: 31, bio: "用户研究与内容整理。", cityCode: "110000", ipRegion: "北京", isFollowing: true, serviceTags: ["用户研究"], tags: nil),
        SoftUserDTO(id: "preview-user-3", phone: nil, nickname: "乔安", avatarUrl: nil, coverUrl: nil, demandCardCoverUrl: nil, creditScore: 84, certificationLevel: "VERIFIED", completedOrders: 19, bio: "数据分析和研究报告。", cityCode: "440300", ipRegion: "深圳", isFollowing: false, serviceTags: ["数据分析"], tags: nil)
    ]

    static let notifications: [NotificationDTO] = [
        NotificationDTO(id: "preview-notice-1", type: "ORDER_WAITING_REVIEW", title: "订单进入待验收", content: "产品需求与用户反馈整理", isRead: false, createdAt: "2026-07-18T04:48:00Z", refId: nil, orderId: "preview-order-02", demandId: nil, path: nil),
        NotificationDTO(id: "preview-notice-2", type: "DEMAND_REQUEST", title: "收到新的接单申请", content: "周屿申请了品牌视觉设计交付", isRead: false, createdAt: "2026-07-18T03:20:00Z", refId: nil, orderId: nil, demandId: "preview-01", path: nil),
        NotificationDTO(id: "preview-notice-3", type: "SYSTEM", title: "认证资料已更新", content: "你的服务标签已经通过审核。", isRead: true, createdAt: "2026-07-17T01:30:00Z", refId: nil, orderId: nil, demandId: nil, path: "/cert-center")
    ]
}

struct ProvidersSearchView: View {
    @Environment(AppSession.self) private var session
    @State private var tagQuery = ""
    @State private var users: [SoftUserDTO] = []
    @State private var selected: SoftUserDTO?
    @State private var isLoading = false
    @State private var searchError: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                NWPaneCaption(text: "按标签检索")
                HStack {
                    NWSearchBar(text: $tagQuery, placeholder: "例如：水电维修") {
                        Task { await search() }
                    }
                    Button("搜索") { Task { await search() } }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 32)
                    Spacer(minLength: 0)
                } else if let searchError, users.isEmpty {
                    NWEmptyState(title: "检索失败", systemImage: "wifi.exclamationmark", message: searchError)
                    Spacer(minLength: 0)
                } else if users.isEmpty {
                    NWEmptyState(title: "输入标签搜索", systemImage: "person.badge.shield.checkmark", message: "查找认证服务者")
                    Spacer(minLength: 0)
                } else {
                    List(users, selection: $selected) { user in
                        HStack(spacing: 10) {
                            NWAvatarView(
                                url: user.avatarMediaURL,
                                name: user.nickname ?? "用户",
                                size: 36
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.nickname ?? "用户").font(.body.weight(.semibold))
                                Text("信用 \(user.creditScore ?? 60)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(user)
                    }
                    .listStyle(.inset)
                }
            }
            .paneColumn(minWidth: 300, idealWidth: 340)

            Divider()
            Group {
                if let selected {
                    UserProfileView(userId: selected.id)
                } else {
                    NWDetailPlaceholder(title: "选择服务者", systemImage: "checkmark.shield")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("认证检索")
    }

    private func search() async {
        let q = tagQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isLoading = true
        searchError = nil
        defer { isLoading = false }
        do {
            users = try await session.certificationService.providers(tags: q)
            selected = users.first
        } catch {
            do {
                users = try await session.userService.searchByTags(q)
                selected = users.first
            } catch {
                users = []
                selected = nil
                searchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

/// 福利中心（渲染图 18，P1）：任务列表 + 详情 + 奖励摘要；设计预览用 fixture，线上走 WelfareService。
struct WelfareCenterView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case tasks = "任务"
        case rewards = "我的奖励"
        var id: String { rawValue }
    }

    /// 兼容旧调用签名；前端复刻模式下忽略外部数据与后端。
    private let previewItems: [WelfareItemDTO]?

    @Environment(AppSession.self) private var session
    @State private var tab: Tab = .tasks
    @State private var tasks: [WelfareDesignTask]
    @State private var recentRewards: [WelfareDesignReward]
    @State private var allRewards: [WelfareDesignReward]
    @State private var selectedID: String
    @State private var claimedIDs: Set<String> = []
    @State private var message: String?
    @State private var isLoadingTasks = false
    @State private var isLoadingRewards = false
    @State private var tasksError: String?
    @State private var rewardsError: String?
    @State private var rewardSummary = WelfareRewardSummary()

    init(previewItems: [WelfareItemDTO]? = nil) {
        self.previewItems = previewItems
        let seed = WelfareDesignFixtures.tasks
        _tasks = State(initialValue: seed)
        _recentRewards = State(initialValue: WelfareDesignFixtures.recentRewards)
        _allRewards = State(initialValue: WelfareDesignFixtures.allRewards)
        _selectedID = State(initialValue: seed.first?.id ?? "")
    }

    private var isDesignPreview: Bool {
        if previewItems != nil { return true }
        let env = ProcessInfo.processInfo.environment["NINEWOOD_DESIGN_PREVIEW"]
        return env == "18-welfare" || env == "18" || env == "welfare"
    }

    private var selected: WelfareDesignTask? {
        tasks.first(where: { $0.id == selectedID }) ?? tasks.first
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            if tab == .tasks {
                HStack(spacing: 0) {
                    taskListPane
                        .paneColumn(minWidth: 340, idealWidth: 380)
                    Divider()
                    Group {
                        if let selected {
                            WelfareTaskDetailPane(
                                task: selected,
                                isClaimed: claimedIDs.contains(selected.id),
                                onClaim: { claim(selected.id) }
                            )
                            .nwStableDetailIdentity(selected.id)
                        } else {
                            NWDetailPlaceholder(title: "选择任务", systemImage: "gift")
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                rewardsPane
            }
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("福利")
        .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("确定", role: .cancel) {}
        } message: { Text(message ?? "") }
        .task {
            guard !isDesignPreview else { return }
            await loadTasks()
            await loadRewards()
        }
        .onChange(of: tab) { _, newTab in
            guard !isDesignPreview, newTab == .rewards, allRewards.isEmpty, !isLoadingRewards else { return }
            Task { await loadRewards() }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 0) {
                ForEach(Tab.allCases) { item in
                    Button {
                        tab = item
                    } label: {
                        Text(item.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tab == item ? .white : AppTheme.secondaryLabel)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(tab == item ? AppTheme.primary : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(AppTheme.fill.opacity(0.7), in: Capsule(style: .continuous))

            Spacer(minLength: 12)

            Label("完成公益服务，获得积分奖励，用行动创造价值", systemImage: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondaryLabel)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(AppTheme.surface)
    }

    private var taskListPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("可领取的任务 \(tasks.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryLabel)
                Spacer(minLength: 8)
                if !isDesignPreview {
                    Button {
                        Task {
                            await loadTasks()
                            await loadRewards()
                        }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryLabel)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoadingTasks || isLoadingRewards)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if !isDesignPreview && isLoadingTasks && tasks.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                Spacer(minLength: 0)
            } else if !isDesignPreview, let tasksError, tasks.isEmpty {
                NWEmptyState(title: "任务加载失败", systemImage: "wifi.exclamationmark", message: tasksError)
                Spacer(minLength: 0)
            } else if tasks.isEmpty {
                NWEmptyState(title: "暂无可领取任务", systemImage: "gift", message: "新的公益任务会显示在这里")
                Spacer(minLength: 0)
            } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(tasks) { task in
                        Button {
                            selectedID = task.id
                        } label: {
                            WelfareTaskListRow(
                                task: task,
                                isSelected: task.id == selected?.id,
                                isClaimed: claimedIDs.contains(task.id)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)

                rewardSummaryCard
                    .padding(.horizontal, 12)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
            }
            }
        }
    }

    private var rewardSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("奖励记录（近 90 天）")
                .font(.system(size: 13, weight: .semibold))

            HStack(spacing: 0) {
                summaryStat(value: rewardSummary.earnedText, label: "已获得")
                summaryStat(value: rewardSummary.completedText, label: "已完成任务")
                summaryStat(value: rewardSummary.inProgressText, label: "进行中任务")
            }

            VStack(spacing: 8) {
                ForEach(displayRecentRewards) { reward in
                    HStack(spacing: 8) {
                        Text(reward.dateLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .frame(width: 52, alignment: .leading)
                        Text(reward.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(reward.pointsLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.urgent)
                        Text(reward.status)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppTheme.openStatus)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.openStatus.opacity(0.12), in: Capsule())
                    }
                }
            }

            Button {
                tab = .rewards
            } label: {
                Text("查看全部奖励记录 ›")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .ninewoodCard()
    }

    private func summaryStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayRecentRewards: [WelfareDesignReward] {
        isDesignPreview ? WelfareDesignFixtures.recentRewards : recentRewards
    }

    private var displayAllRewards: [WelfareDesignReward] {
        isDesignPreview ? WelfareDesignFixtures.allRewards : allRewards
    }

    private var rewardsPane: some View {
        Group {
            if !isDesignPreview && isLoadingRewards && allRewards.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !isDesignPreview, let rewardsError, allRewards.isEmpty {
                NWEmptyState(title: "奖励加载失败", systemImage: "wifi.exclamationmark", message: rewardsError)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayAllRewards.isEmpty {
                NWEmptyState(title: "暂无奖励记录", systemImage: "gift", message: "完成公益任务后奖励会显示在这里")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    rewardHero(title: "累计实收", value: rewardSummary.earnedText)
                    rewardHero(title: "已完成", value: rewardSummary.completedText)
                    rewardHero(title: "进行中", value: rewardSummary.inProgressText)
                }

                ForEach(displayAllRewards) { reward in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reward.title)
                                .font(.system(size: 14, weight: .semibold))
                            Text(reward.dateLabel)
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.secondaryLabel)
                        }
                        Spacer()
                        Text(reward.pointsLabel)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppTheme.urgent)
                        Text(reward.status)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.openStatus)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppTheme.openStatus.opacity(0.12), in: Capsule())
                    }
                    .padding(14)
                    .ninewoodCard()
                }
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.workspaceBackground)
            }
        }
    }

    private func rewardHero(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondaryLabel)
            Text(value)
                .font(.system(size: 18, weight: .bold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninewoodCard()
    }

    private func claim(_ id: String) {
        guard !claimedIDs.contains(id) else { return }
        if isDesignPreview {
            claimedIDs.insert(id)
            message = "已领取任务，主办方将与你联系确认服务安排。"
            return
        }
        Task {
            do {
                try await session.welfareService.claim(demandId: id)
                claimedIDs.insert(id)
                message = "已领取任务，主办方将与你联系确认服务安排。"
                await loadTasks()
                await loadRewards()
            } catch {
                message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func loadTasks() async {
        if isDesignPreview {
            tasks = WelfareDesignFixtures.tasks
            selectedID = tasks.first?.id ?? selectedID
            return
        }
        isLoadingTasks = true
        tasksError = nil
        defer { isLoadingTasks = false }
        do {
            let rows = try await session.welfareService.list()
            let mapped = rows.map(mapWelfareTask)
            tasks = mapped
            claimedIDs.formUnion(Set(rows.compactMap { dto in
                let status = dto.status?.uppercased() ?? ""
                return status == "CLAIMED" || status == "COMPLETED" ? dto.id : nil
            }))
            if let selected = mapped.first(where: { $0.id == selectedID }) {
                selectedID = selected.id
            } else {
                selectedID = mapped.first?.id ?? ""
            }
        } catch {
            tasks = []
            selectedID = ""
            tasksError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadRewards() async {
        if isDesignPreview {
            recentRewards = WelfareDesignFixtures.recentRewards
            allRewards = WelfareDesignFixtures.allRewards
            rewardSummary = WelfareRewardSummary(
                earnedText: "850 点",
                completedText: "3 个",
                inProgressText: "1 个"
            )
            return
        }
        isLoadingRewards = true
        rewardsError = nil
        defer { isLoadingRewards = false }
        do {
            let page = try await session.welfareService.rewards()
            let mapped = page.rows.map(mapWelfareReward)
            allRewards = mapped
            recentRewards = Array(mapped.prefix(2))
            rewardSummary = WelfareRewardSummary(page: page, rewards: mapped)
        } catch {
            allRewards = []
            recentRewards = []
            rewardSummary = WelfareRewardSummary()
            rewardsError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func mapWelfareTask(_ dto: WelfareItemDTO) -> WelfareDesignTask {
        let title = dto.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "公益任务"
        let description = dto.description?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "完成公益服务，获得积分奖励。"
        let parts = description.split(separator: "·", omittingEmptySubsequences: true).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let location = parts.first ?? "远程"
        let serviceType = parts.dropFirst().first ?? "公益服务"
        let rewardPoints = Int(truncating: (dto.rewardPoints?.value ?? 0) as NSDecimalNumber)
        let status = dto.status?.uppercased() ?? "OPEN"
        let eligibility = status == "OPEN" ? "符合条件" : status

        return WelfareDesignTask(
            id: dto.id,
            title: title,
            location: location,
            serviceType: serviceType,
            category: welfareCategory(for: status),
            deadline: "—",
            rewardPoints: rewardPoints,
            filledSlots: 0,
            totalSlots: 0,
            eligibility: eligibility,
            icon: "gift.fill",
            iconTint: AppTheme.primary,
            purpose: description,
            expectedResult: description,
            requirements: [],
            servicePeriod: "—",
            auditNote: "完成服务并经主办方审核通过后发放积分。",
            organizerName: "九木公益协作",
            organizerMeta: "平台公益项目",
            organizerContact: "领取后站内消息联系",
            privacyNote: "请保护服务对象隐私，未经允许不得对外传播相关材料。"
        )
    }

    private func mapWelfareReward(_ dto: WelfareRewardDTO) -> WelfareDesignReward {
        WelfareDesignReward(
            id: dto.id,
            title: dto.displayTitle,
            dateLabel: welfareRewardDateLabel(for: dto.createdAt),
            pointsLabel: welfareRewardPointsLabel(for: dto),
            status: welfareRewardStatus(for: dto)
        )
    }

    private func welfareCategory(for status: String) -> String {
        switch status {
        case "OPEN": "开放"
        case "CLAIMED": "已领取"
        case "COMPLETED": "已完成"
        default: status
        }
    }

    private func welfareRewardDateLabel(for iso: String?) -> String {
        guard let date = APIDate.parse(iso) else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func welfareRewardPointsLabel(for dto: WelfareRewardDTO) -> String {
        if dto.isSpiritualReward {
            return dto.badge ?? "精神激励"
        }
        let amount = dto.amount?.value ?? 0
        return "+\(amount.pointsText)"
    }

    private func welfareRewardStatus(for dto: WelfareRewardDTO) -> String {
        if dto.isSpiritualReward { return "精神激励" }
        if let badge = dto.badge?.trimmingCharacters(in: .whitespacesAndNewlines), !badge.isEmpty {
            return badge
        }
        return "已发放"
    }
}

// MARK: - Welfare list / detail

private struct WelfareTaskListRow: View {
    let task: WelfareDesignTask
    var isSelected: Bool
    var isClaimed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: task.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(task.iconTint)
                .frame(width: 40, height: 40)
                .background(task.iconTint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.onSurface)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("\(task.location) · \(task.serviceType)")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
                HStack(spacing: 6) {
                    Text(task.category)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.primary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(AppTheme.softPrimary, in: Capsule())
                    Text(task.deadline)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryLabel)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 5) {
                Text("\(task.rewardPoints) 点")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.urgent)
                Text("名额 \(task.filledSlots)/\(task.totalSlots)")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
                Text(isClaimed ? "已领取" : task.eligibility)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isClaimed ? AppTheme.secondaryLabel : AppTheme.openStatus)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? AppTheme.softPrimary : AppTheme.surface)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSelected ? AppTheme.primary : AppTheme.outlineVariant,
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
    }
}

private struct WelfareTaskDetailPane: View {
    let task: WelfareDesignTask
    var isClaimed: Bool
    var onClaim: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(task.title)
                        .font(.system(size: 22, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)

                    detailBlock(icon: "flag", title: "项目目的", body: task.purpose)
                    detailBlock(icon: "checkmark.seal", title: "期待成果", body: task.expectedResult)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("服务内容与要求", systemImage: "list.bullet")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        ForEach(task.requirements, id: \.self) { line in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                Text(line)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.system(size: 13))
                        }
                    }

                    detailBlock(icon: "calendar", title: "服务时间", body: task.servicePeriod)
                    detailBlock(icon: "shield.checkered", title: "审核与认证", body: task.auditNote)

                    HStack(spacing: 8) {
                        Label("奖励", systemImage: "gift")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Text("\(task.rewardPoints) 点")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(AppTheme.urgent)
                    }

                    organizerBlock

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.shield")
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Text(task.privacyNote)
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(AppTheme.surfaceLow, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .padding(28)
                .frame(maxWidth: 680, alignment: .leading)
            }

            Divider()

            VStack(spacing: 8) {
                Button(action: onClaim) {
                    Text(isClaimed ? "已领取" : "领取任务")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            (isClaimed ? AppTheme.secondaryLabel.opacity(0.45) : AppTheme.primary),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isClaimed)

                Text("领取后将与主办方建立联系，确认服务时间与材料要求。")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(AppTheme.surface)
        }
        .background(AppTheme.workspaceBackground)
    }

    private func detailBlock(icon: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryLabel)
            Text(body)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.onSurface.opacity(0.9))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var organizerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("主办方", systemImage: "building.2")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryLabel)

            HStack(spacing: 8) {
                Text(task.organizerName)
                    .font(.system(size: 14, weight: .semibold))
                Text("已认证")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(AppTheme.softPrimary, in: Capsule())
            }

            Text(task.organizerMeta)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondaryLabel)
            Text(task.organizerContact)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondaryLabel)
        }
    }
}

// MARK: - Welfare design model

private struct WelfareDesignTask: Identifiable, Hashable {
    let id: String
    let title: String
    let location: String
    let serviceType: String
    let category: String
    let deadline: String
    let rewardPoints: Int
    let filledSlots: Int
    let totalSlots: Int
    let eligibility: String
    let icon: String
    let iconTint: Color
    let purpose: String
    let expectedResult: String
    let requirements: [String]
    let servicePeriod: String
    let auditNote: String
    let organizerName: String
    let organizerMeta: String
    let organizerContact: String
    let privacyNote: String
}

private struct WelfareDesignReward: Identifiable, Hashable {
    let id: String
    let title: String
    let dateLabel: String
    let pointsLabel: String
    let status: String
}

private enum WelfareDesignFixtures {
    static let tasks: [WelfareDesignTask] = [
        WelfareDesignTask(
            id: "preview-welfare-1",
            title: "为社区长者整理智能手机使用指南",
            location: "上海市",
            serviceType: "线下服务",
            category: "长者",
            deadline: "截止 05-30",
            rewardPoints: 300,
            filledSlots: 8,
            totalSlots: 15,
            eligibility: "符合条件",
            icon: "person.2.fill",
            iconTint: AppTheme.primary,
            purpose: "帮助社区长者掌握智能手机常用功能，降低数字鸿沟，提升日常沟通与生活便利。",
            expectedResult: "完成一份图文并茂的使用指南，并组织 2–3 次线下分享辅导，确保参与长者能独立完成基础操作。",
            requirements: [
                "指南覆盖微信、支付、出行与就医预约等场景，篇幅约 8–12 页",
                "具备耐心沟通能力，可用通俗语言讲解",
                "线下服务 2–3 次，每次约 2 小时"
            ],
            servicePeriod: "2025-05-22 — 2025-06-15",
            auditNote: "服务完成后提交现场照片与长者反馈摘要，主办方审核通过后发放积分。",
            organizerName: "上海市徐汇区社区服务中心",
            organizerMeta: "政府单位 · 成立于 2006 · 关注 2.4k",
            organizerContact: "联系电话 021-6488**** · 工作日 09:00–17:00",
            privacyNote: "服务过程中请保护长者个人信息，不得拍摄含证件号、住址的材料，不得对外传播。"
        ),
        WelfareDesignTask(
            id: "preview-welfare-2",
            title: "社区无障碍体验检查",
            location: "上海市",
            serviceType: "线上+线下",
            category: "无障碍",
            deadline: "截止 06-08",
            rewardPoints: 220,
            filledSlots: 3,
            totalSlots: 10,
            eligibility: "符合条件",
            icon: "accessibility",
            iconTint: AppTheme.openStatus,
            purpose: "检查关键公共服务流程的键盘操作与文字可读性，输出可落地的改进清单。",
            expectedResult: "提交一份无障碍问题清单与优先级建议，覆盖至少 3 个高频场景。",
            requirements: [
                "熟悉 VoiceOver / 键盘导航基础",
                "按模板记录复现步骤与截图",
                "需参加一次线上说明会"
            ],
            servicePeriod: "2025-05-25 — 2025-06-20",
            auditNote: "提交报告后由无障碍顾问复核，通过后发放积分。",
            organizerName: "九木公益协作站",
            organizerMeta: "社会组织 · 成立于 2019 · 关注 1.1k",
            organizerContact: "邮箱 a11y@ninewood.example · 工作日回复",
            privacyNote: "测试账号由主办方提供，请勿使用真实个人敏感数据。"
        ),
        WelfareDesignTask(
            id: "preview-welfare-3",
            title: "公益组织活动海报排版",
            location: "远程",
            serviceType: "线上服务",
            category: "设计",
            deadline: "截止 05-28",
            rewardPoints: 160,
            filledSlots: 5,
            totalSlots: 8,
            eligibility: "符合条件",
            icon: "paintbrush.fill",
            iconTint: Color(red: 0.55, green: 0.40, blue: 0.85),
            purpose: "协助公益组织整理活动信息层级，完成一版可发布海报。",
            expectedResult: "交付可印刷与可线上传播的海报源文件（含标题、时间、地点、报名方式）。",
            requirements: [
                "熟悉基础排版与可读性规范",
                "提供 1 次修改",
                "交付期限 5 个工作日"
            ],
            servicePeriod: "领取后 5 个工作日",
            auditNote: "主办方确认可用后发放积分。",
            organizerName: "青柠公益传播小组",
            organizerMeta: "志愿者团队 · 成立于 2021",
            organizerContact: "微信群内对接 · 工作日 10:00–18:00",
            privacyNote: "活动素材仅用于本次公益传播，未经允许不得商用。"
        ),
        WelfareDesignTask(
            id: "preview-welfare-4",
            title: "帮助新用户完成第一份需求说明",
            location: "远程",
            serviceType: "线上辅导",
            category: "成长",
            deadline: "截止 06-12",
            rewardPoints: 80,
            filledSlots: 12,
            totalSlots: 30,
            eligibility: "符合条件",
            icon: "book.fill",
            iconTint: AppTheme.human,
            purpose: "用经验帮助新用户写出清晰、可执行的第一份需求说明。",
            expectedResult: "完成一次需求点评，并给出可执行修改建议。",
            requirements: [
                "至少完成过 3 单需求协作",
                "点评需覆盖目标、范围与验收标准",
                "回复时限 48 小时"
            ],
            servicePeriod: "滚动进行",
            auditNote: "被辅导用户确认有帮助后发放积分。",
            organizerName: "九木成长计划",
            organizerMeta: "平台项目 · 长期开放",
            organizerContact: "站内消息 · 自动分派",
            privacyNote: "辅导内容仅双方可见，请勿泄露对方草稿中的商业信息。"
        ),
        WelfareDesignTask(
            id: "preview-welfare-5",
            title: "社区图书角整理与导读",
            location: "杭州市",
            serviceType: "线下服务",
            category: "文化",
            deadline: "截止 06-01",
            rewardPoints: 180,
            filledSlots: 4,
            totalSlots: 12,
            eligibility: "符合条件",
            icon: "leaf.fill",
            iconTint: AppTheme.openStatus,
            purpose: "整理社区图书角分类，并为儿童读者准备一次短导读。",
            expectedResult: "完成分类标签与一次 30 分钟导读活动。",
            requirements: [
                "可周末到场",
                "具备基础活动组织经验",
                "提交活动照片与清单"
            ],
            servicePeriod: "2025-05-24 — 2025-06-01",
            auditNote: "社区管理员验收后发放积分。",
            organizerName: "杭州市滨江社区文化站",
            organizerMeta: "政府单位 · 成立于 2012",
            organizerContact: "电话 0571-866****",
            privacyNote: "活动中注意未成年人隐私，勿公开面部特写。"
        ),
        WelfareDesignTask(
            id: "preview-welfare-6",
            title: "环保倡议文案校对",
            location: "远程",
            serviceType: "线上服务",
            category: "环保",
            deadline: "截止 05-26",
            rewardPoints: 90,
            filledSlots: 6,
            totalSlots: 20,
            eligibility: "符合条件",
            icon: "heart.fill",
            iconTint: AppTheme.error.opacity(0.85),
            purpose: "校对环保倡议文案的事实表述与语气，避免夸大承诺。",
            expectedResult: "提交带批注的校对稿与修改建议。",
            requirements: [
                "中文表达清晰",
                "熟悉基础事实核查",
                "2 个工作日内返回"
            ],
            servicePeriod: "领取后 2 个工作日",
            auditNote: "编辑确认后发放积分。",
            organizerName: "绿行计划",
            organizerMeta: "社会组织 · 成立于 2018",
            organizerContact: "email@green.example",
            privacyNote: "文稿未发布前请勿外传。"
        )
    ]

    static let recentRewards: [WelfareDesignReward] = [
        WelfareDesignReward(id: "r1", title: "社区图书角整理…", dateLabel: "05-12", pointsLabel: "+250 点", status: "已发放"),
        WelfareDesignReward(id: "r2", title: "新用户需求辅导", dateLabel: "04-28", pointsLabel: "+80 点", status: "已发放")
    ]

    static let allRewards: [WelfareDesignReward] = [
        WelfareDesignReward(id: "r1", title: "社区图书角整理与导读", dateLabel: "2025-05-12", pointsLabel: "+250 点", status: "已发放"),
        WelfareDesignReward(id: "r2", title: "帮助新用户完成第一份需求说明", dateLabel: "2025-04-28", pointsLabel: "+80 点", status: "已发放"),
        WelfareDesignReward(id: "r3", title: "公益组织活动海报排版", dateLabel: "2025-04-10", pointsLabel: "+160 点", status: "已发放"),
        WelfareDesignReward(id: "r4", title: "为社区长者整理智能手机使用指南", dateLabel: "进行中", pointsLabel: "300 点", status: "进行中")
    ]
}

enum WelfareDesignPreviewFixtures {
    static let items: [WelfareItemDTO] = [
        WelfareItemDTO(id: "preview-welfare-1", title: "为社区长者整理智能手机使用指南", description: "上海市 · 线下服务 · 300 点奖励", status: "OPEN", rewardPoints: FlexibleDecimal(300)),
        WelfareItemDTO(id: "preview-welfare-2", title: "社区无障碍体验检查", description: "上海市 · 线上+线下 · 220 点奖励", status: "OPEN", rewardPoints: FlexibleDecimal(220)),
        WelfareItemDTO(id: "preview-welfare-3", title: "公益组织活动海报排版", description: "远程 · 线上服务 · 160 点奖励", status: "OPEN", rewardPoints: FlexibleDecimal(160))
    ]
}

private struct WelfareRewardSummary {
    let earnedText: String
    let completedText: String
    let inProgressText: String

    init(
        earnedText: String = "0 点",
        completedText: String = "0 个",
        inProgressText: String = "0 个"
    ) {
        self.earnedText = earnedText
        self.completedText = completedText
        self.inProgressText = inProgressText
    }

    init(page: WelfareRewardsPage, rewards: [WelfareDesignReward]) {
        if let totalEarned = page.totalEarned?.value {
            earnedText = totalEarned.pointsText
        } else {
            let total = rewards.reduce(Decimal.zero) { partial, reward in
                partial + Self.points(from: reward.pointsLabel)
            }
            earnedText = total.pointsText
        }
        let completed = rewards.filter { $0.status.contains("已发放") || $0.status.contains("精神") }.count
        let inProgress = rewards.filter { $0.status.contains("进行") }.count
        completedText = "\(completed) 个"
        inProgressText = "\(inProgress) 个"
    }

    private static func points(from label: String) -> Decimal {
        let digits = label.filter { $0.isNumber || $0 == "." }
        return Decimal(string: digits) ?? 0
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var nickname = ""
    @State private var bio = ""
    @State private var isBusy = false
    @State private var myTags: [String] = []
    @State private var tagDraft = ""
    @State private var blockTags = ""
    @State private var blockKeywords = ""
    @State private var receivePushes = true
    @State private var pushFrequency = "NORMAL"
    @State private var excludeKeywords = ""
    @State private var excludeTags = ""
    @State private var avatarItem: PhotosPickerItem?
    @State private var coverItem: PhotosPickerItem?
    @State private var pendingAvatar: MultipartFile?
    @State private var pendingCover: MultipartFile?
    @State private var message: String?

    private let pushFrequencyOptions: [(id: String, label: String)] = [
        ("HIGH", "高频"),
        ("NORMAL", "正常"),
        ("LOW", "低频"),
        ("OFF", "关闭"),
    ]

    private var isDesignPreview: Bool {
        let env = ProcessInfo.processInfo.environment["NINEWOOD_DESIGN_PREVIEW"]
        return env == "20-settings" || env == "settings" || env == "20"
    }

    var body: some View {
        DocumentShell(maxWidth: 1040) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: AppTheme.space24) {
                    profileSettings
                        .frame(maxWidth: .infinity)
                    settingsAside
                        .frame(width: 320)
                }

                VStack(alignment: .leading, spacing: AppTheme.space24) {
                    profileSettings
                    settingsAside
                }
            }
        }
        .navigationTitle("设置")
        .onAppear {
            if isDesignPreview {
                seedDesignPreviewContent()
            }
        }
        .task {
            guard !isDesignPreview else { return }
            await load()
        }
    }

    private func seedDesignPreviewContent() {
        nickname = "林间有风"
        bio = "保持好奇，保持热爱。"
        isBusy = true
        myTags = ["设计", "产品", "运营", "开发", "写作"]
        blockTags = "营销,广告,骚扰"
        blockKeywords = blockTags
        receivePushes = true
        pushFrequency = "NORMAL"
        excludeKeywords = "兼职,广告"
        excludeTags = "营销"
    }

    private var profileSettings: some View {
        VStack(alignment: .leading, spacing: AppTheme.space24) {
            section("个人资料") {
                if isDesignPreview {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("头像与封面").font(.subheadline.weight(.semibold))
                        HStack(spacing: 12) {
                            Group {
                                if NSImage(named: "AvatarLinXia") != nil {
                                    Image("AvatarLinXia").resizable().scaledToFill()
                                } else {
                                    Circle().fill(AppTheme.fill)
                                }
                            }
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                            RoundedRectangle(cornerRadius: 8)
                                .fill(AppTheme.softPrimary)
                                .frame(height: 72)
                                .overlay {
                                    Text("封面")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                        }
                        Text("支持 JPG、PNG、WebP 格式，头像建议 512×512，封面建议 1600×400。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                } else {
                    HStack(spacing: AppTheme.space16) {
                        NWAvatarView(
                            url: session.currentUser?.avatarMediaURL,
                            name: nickname.isEmpty ? "九木用户" : nickname,
                            size: 72
                        )
                        VStack(alignment: .leading, spacing: 5) {
                            Text("头像与封面")
                                .font(.subheadline.weight(.semibold))
                            Text("资料会展示在需求、应标与协作页面")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                PhotosPicker(selection: $avatarItem, matching: .images) {
                                    Text(pendingAvatar == nil ? "更换头像" : "已选头像")
                                        .font(.caption)
                                }
                                PhotosPicker(selection: $coverItem, matching: .images) {
                                    Text(pendingCover == nil ? "更换封面" : "已选封面")
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    .onChange(of: avatarItem) { _, item in
                        Task { await loadAvatar(item) }
                    }
                    .onChange(of: coverItem) { _, item in
                        Task { await loadCover(item) }
                    }
                    Divider()
                }

                settingsField("昵称") {
                    TextField("昵称", text: $nickname)
                        .textFieldStyle(.roundedBorder)
                }
                settingsField("个人简介") {
                    TextEditor(text: $bio)
                        .frame(minHeight: 82)
                        .padding(6)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(AppTheme.outlineVariant)
                        }
                }

                HStack {
                    Text("状态")
                    Spacer()
                    if isDesignPreview {
                        HStack(spacing: 6) {
                            Circle().fill(AppTheme.openStatus).frame(width: 8, height: 8)
                            Text("忙碌")
                                .font(.subheadline)
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Toggle("忙碌中", isOn: $isBusy)
                            .toggleStyle(.switch)
                            .onChange(of: isBusy) { _, value in
                                Task { await saveBusy(value) }
                            }
                    }
                }

                Divider()

                settingsField("技能标签") {
                    if isDesignPreview {
                        HStack {
                            ForEach(myTags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(AppTheme.fill.opacity(0.35), in: Capsule())
                            }
                            Button("+ 添加标签") {}
                                .font(.caption)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        Text("添加你的技能标签，帮助他人更好地了解你。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        tagEditor
                    }
                }

                Divider()

                settingsField("屏蔽关键词") {
                    if isDesignPreview {
                        HStack {
                            ForEach(["营销", "广告", "骚扰"], id: \.self) { word in
                                Text(word)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(AppTheme.fill.opacity(0.35), in: Capsule())
                            }
                            Button("+ 添加关键词") {}
                                .font(.caption)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        Text("包含以上关键词的内容将被屏蔽。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: AppTheme.space8) {
                            TextField("标签（逗号分隔）", text: $blockTags)
                                .textFieldStyle(.roundedBorder)
                            TextField("关键词（逗号分隔）", text: $blockKeywords)
                                .textFieldStyle(.roundedBorder)
                            Text("包含这些标签或关键词的内容将减少展示。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                settingsField("需求推送") {
                    if isDesignPreview {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("接收匹配推送", isOn: .constant(true))
                                .toggleStyle(.switch)
                            Text("推送频率：正常")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: AppTheme.space8) {
                            Toggle("接收匹配推送", isOn: $receivePushes)
                                .toggleStyle(.switch)
                                .onChange(of: receivePushes) { _, _ in
                                    Task { await savePushPreferences() }
                                }
                            Picker("推送频率", selection: $pushFrequency) {
                                ForEach(pushFrequencyOptions, id: \.id) { option in
                                    Text(option.label).tag(option.id)
                                }
                            }
                            .disabled(!receivePushes)
                            .onChange(of: pushFrequency) { _, _ in
                                Task { await savePushPreferences() }
                            }
                            Text("控制站内匹配需求推送的接收与频率。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("排除关键词（逗号分隔）", text: $excludeKeywords)
                                .textFieldStyle(.roundedBorder)
                            TextField("排除标签（逗号分隔）", text: $excludeTags)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                HStack {
                    if let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(AppTheme.openStatus)
                    }
                    Spacer()
                    if isDesignPreview {
                        NWPrimaryCTA(title: "保存")
                            .frame(width: 120)
                    } else {
                        Button("保存") {
                            Task {
                                await saveProfile()
                                await saveBlocklist()
                                await savePushPreferences()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: AppTheme.space8) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 72), spacing: 6)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(myTags, id: \.self) { tag in
                    Button {
                        myTags.removeAll { $0 == tag }
                        Task { await saveTags() }
                    } label: {
                        Label(tag, systemImage: "xmark")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            HStack {
                TextField("添加标签", text: $tagDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTag() }
                Button("添加") { addTag() }
                    .disabled(tagDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var settingsAside: some View {
        VStack(alignment: .leading, spacing: AppTheme.space24) {
            section("接口与版本") {
                settingsField("API 地址") {
                    Text(isDesignPreview ? "https://api.ninewood.app" : APIConfig.baseURL.absoluteString)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .padding(AppTheme.space8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.fill.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                }
                settingsField("应用版本") {
                    Text(isDesignPreview ? "1.2.0 (120)" : (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"))
                }
                Label("已是最新版本", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.openStatus)
            }

            section("法律与协议") {
                settingsLink("用户协议", destination: LegalDocView(kind: .terms))
                Divider()
                settingsLink("隐私政策", destination: LegalDocView(kind: .privacy))
                Divider()
                settingsLink("开源许可", destination: LegalDocView(kind: .licenses))
            }

            section("账户操作") {
                Button(role: .destructive) {
                    Task { await session.logout() }
                } label: {
                    Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Text("退出后将清除本地会话信息。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func settingsField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func settingsLink<Destination: View>(
        _ title: String,
        destination: Destination
    ) -> some View {
        NavigationLink {
            destination
        } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .padding(16)
        .ninewoodCard()
    }

    private func addTag() {
        let tag = tagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty, !myTags.contains(tag) else { return }
        myTags.append(tag)
        tagDraft = ""
        Task { await saveTags() }
    }

    private func load() async {
        nickname = session.currentUser?.nickname ?? ""
        do {
            let me = try await session.userService.me()
            bio = me.bio ?? ""
            nickname = me.nickname ?? nickname
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        do {
            myTags = try await session.userService.myTags()
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        do {
            let busy = try await session.userService.busyStatus()
            isBusy = busy.isBusy ?? false
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        do {
            let bl = try await session.userService.fetchBlocklist()
            blockTags = bl.tags.joined(separator: ",")
            blockKeywords = bl.keywords.joined(separator: ",")
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        do {
            let pref = try await session.userService.fetchPushPreferences()
            receivePushes = pref.receivePushes ?? true
            pushFrequency = pref.pushFrequency ?? "NORMAL"
            excludeKeywords = (pref.excludeKeywords ?? []).joined(separator: ",")
            excludeTags = (pref.excludeTags ?? []).joined(separator: ",")
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func saveProfile() async {
        do {
            let nick = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            let bioText = bio.trimmingCharacters(in: .whitespacesAndNewlines)
            if pendingAvatar != nil || pendingCover != nil {
                _ = try await session.userService.updateProfileMultipart(
                    nickname: nick,
                    bio: bioText,
                    avatar: pendingAvatar,
                    cover: pendingCover
                )
                pendingAvatar = nil
                pendingCover = nil
                avatarItem = nil
                coverItem = nil
            } else {
                _ = try await session.userService.updateProfile(
                    nickname: nick,
                    bio: bioText
                )
            }
            message = "资料已保存"
            await session.retryBootstrap()
        } catch {
            message = error.localizedDescription
        }
    }

    private func saveBlocklist() async {
        let tags = blockTags.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let keywords = blockKeywords.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        do {
            try await session.userService.updateBlocklist(tags: tags, keywords: keywords)
            message = "屏蔽规则已保存"
        } catch {
            message = error.localizedDescription
        }
    }

    private func saveBusy(_ value: Bool) async {
        do {
            try await session.userService.updateBusy(isBusy: value)
        } catch {
            message = error.localizedDescription
            isBusy = !value
        }
    }

    private func saveTags() async {
        do {
            try await session.userService.updateTags(myTags)
            message = "标签已更新"
        } catch {
            message = error.localizedDescription
        }
    }

    private func savePushPreferences() async {
        let keywords = excludeKeywords
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let tags = excludeTags
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        do {
            _ = try await session.userService.updatePushPreferences(
                receivePushes: receivePushes,
                pushFrequency: receivePushes ? pushFrequency : "OFF",
                excludeKeywords: keywords,
                excludeTags: tags
            )
            message = "推送偏好已保存"
        } catch {
            message = error.localizedDescription
        }
    }

    private func loadAvatar(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else { return }
        pendingAvatar = MultipartFile(
            fieldName: "avatar",
            fileName: "avatar.jpg",
            mimeType: "image/jpeg",
            data: data
        )
    }

    private func loadCover(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else { return }
        pendingCover = MultipartFile(
            fieldName: "cover",
            fileName: "cover.jpg",
            mimeType: "image/jpeg",
            data: data
        )
    }
}

struct LegalDocView: View {
    enum Kind: String, Identifiable {
        case privacy, terms, licenses
        var id: String { rawValue }
        var title: String {
            switch self {
            case .privacy: "隐私政策"
            case .terms: "用户协议"
            case .licenses: "开源许可"
            }
        }
    }

    let kind: Kind

    var body: some View {
        DocumentShell(maxWidth: AppTheme.documentWideMaxWidth) {
            Text(bodyText)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .navigationTitle(kind.title)
    }

    private var bodyText: String {
        switch kind {
        case .privacy:
            """
            九木（Ninewood）重视你的隐私。我们仅收集提供服务所必需的信息，包括账号手机号、资料、交易与沟通记录，以及设备与日志信息用于安全与排障。

            数据用途：身份验证、需求匹配、订单托管与结算、消息推送、风控与客服。我们不会向无关第三方出售个人数据。

            你可在「设置」中更新资料与屏蔽规则；如需注销或导出数据，请联系平台支持。完整条款以 tothetomorrow.com 公示版本为准。
            """
        case .terms:
            """
            使用九木即表示你同意：如实发布需求与服务信息；不得利用平台从事违法、欺诈或骚扰行为；交易资金经平台点数钱包托管与结算，服务费按订单规则收取。

            正式接单前的「请求接单 / 应标」仅用于沟通，不构成合同。验收确认后完成结算；争议由平台依据提交证据调解。

            平台可在合理范围内更新本协议，重大变更将通过应用内通知。继续使用即视为接受更新后的条款。
            """
        case .licenses:
            """
            本应用使用开源组件，包括但不限于 Socket.IO Client Swift、Starscream 等，遵循其各自许可证（MIT 等）。

            九木客户端与服务端代码版权归项目维护者所有。第三方字体与图标资源遵循其来源许可。
            """
        }
    }
}
