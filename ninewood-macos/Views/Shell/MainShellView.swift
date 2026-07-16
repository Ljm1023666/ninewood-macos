import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case discover
    case cardPool
    case publish
    case circles
    case loops
    case searchPeople
    case messages
    case cert
    case help
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discover: "发现"
        case .cardPool: "卡池"
        case .publish: "发布"
        case .circles: "圈子"
        case .cert: "认证"
        case .help: "帮助"
        case .loops: "自然回"
        case .searchPeople: "找人"
        case .messages: "消息"
        case .profile: "我的"
        }
    }

    var systemImage: String {
        switch self {
        case .discover: "house"
        case .cardPool: "square.stack.3d.up"
        case .publish: "doc.badge.plus"
        case .circles: "person.3"
        case .cert: "checkmark.shield"
        case .help: "questionmark.circle"
        case .loops: "arrow.triangle.2.circlepath"
        case .searchPeople: "magnifyingglass"
        case .messages: "bubble.left.and.bubble.right"
        case .profile: "person"
        }
    }

    static let primary: [SidebarItem] = [.discover, .cardPool, .publish, .circles]
    static let collab: [SidebarItem] = [.loops, .searchPeople, .messages]
    static let account: [SidebarItem] = [.cert, .help, .profile]
}

struct MainShellView: View {
    @Environment(AppSession.self) private var session
    @State private var selection: SidebarItem? = .discover
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: AppTheme.sidebarWidth, max: 260)
        } detail: {
            detail(for: selection ?? .discover)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(AppTheme.primary)
        .task {
            await session.refreshUnread()
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section("主区") {
                ForEach(SidebarItem.primary) { item in
                    sidebarRow(item)
                }
            }

            Section("协作") {
                ForEach(SidebarItem.collab) { item in
                    sidebarRow(item)
                }
            }

            Section("账户") {
                ForEach(SidebarItem.account) { item in
                    sidebarRow(item)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            brandHeader
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                Task { await session.logout() }
            } label: {
                Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(AppTheme.space16)
            .overlay(alignment: .top) {
                Divider()
            }
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            Text("N")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("九木")
                    .font(.headline)
                Text("Ninewood")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, AppTheme.space12)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        Label {
            HStack {
                Text(item.title)
                Spacer()
                if item == .messages, session.unreadMessageCount > 0 {
                    Text(session.unreadMessageCount > 99 ? "99+" : "\(session.unreadMessageCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.error, in: Capsule())
                }
            }
        } icon: {
            Image(systemName: item.systemImage)
        }
        .tag(item)
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .discover:
            DiscoverView()
        case .publish:
            CreateDemandView(embedded: true)
        case .loops:
            NaturalLoopWorkspaceView()
        case .messages:
            MessagesView()
        case .profile:
            ProfileView()
        case .cardPool:
            CardPoolView()
        case .circles:
            CirclesView()
        case .cert:
            CertCenterView()
        case .help:
            HelpView()
        case .searchPeople:
            FindPeopleView()
        }
    }
}
