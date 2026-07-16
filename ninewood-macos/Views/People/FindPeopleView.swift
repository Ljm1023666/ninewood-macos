import SwiftUI

struct FindPeopleView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case search = "搜索"
        case certified = "认证服务者"
        var id: String { rawValue }
    }

    @Environment(AppSession.self) private var session
    @State private var tab: Tab = .search
    @State private var keyword = ""
    @State private var results: [SoftUserDTO] = []
    @State private var selected: SoftUserDTO?
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var didSearch = false

    var body: some View {
        HStack(spacing: 0) {
            listPane
                .paneColumn(minWidth: 320, idealWidth: 360)

            Divider()

            Group {
                if let selected {
                    UserProfileView(userId: selected.id)
                } else {
                    NWDetailPlaceholder(
                        title: "选择用户",
                        systemImage: "person.crop.circle",
                        message: tab == .certified
                            ? "搜索认证服务者后从左侧选择查看资料"
                            : "搜索后从左侧选择一位用户查看资料"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("找人")
        .onChange(of: tab) { _, _ in
            results = []
            selected = nil
            searchError = nil
            didSearch = false
            keyword = ""
        }
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            NWPaneCaption(text: "搜索服务者或用户")

            Picker("模式", selection: $tab) {
                ForEach(Tab.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AppTheme.space16)
            .padding(.bottom, AppTheme.space12)

            HStack(spacing: 10) {
                NWSearchBar(
                    text: $keyword,
                    placeholder: tab == .certified ? "标签关键词（可选）" : "搜索昵称 / 关键词"
                ) {
                    Task { await search() }
                }
                Button {
                    Task { await search() }
                } label: {
                    Text("搜索")
                        .frame(minWidth: 56)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSearching || (tab == .search && keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            if let searchError {
                Text(searchError)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                Spacer(minLength: 0)
            } else if isSearching && results.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                Spacer(minLength: 0)
            } else if didSearch && results.isEmpty {
                NWEmptyState(
                    title: tab == .certified ? "没有找到认证服务者" : "没有找到用户",
                    systemImage: "person.slash",
                    message: "换个关键词试试"
                )
                Spacer(minLength: 0)
            } else if !didSearch {
                NWEmptyState(
                    title: tab == .certified ? "查找认证服务者" : "开始搜索",
                    systemImage: "magnifyingglass",
                    message: tab == .certified
                        ? "可按标签筛选，或直接搜索全部认证服务者"
                        : "输入昵称关键词，查找服务者或用户"
                )
                Spacer(minLength: 0)
            } else {
                List(results, selection: $selected) { user in
                    UserRowView(user: user)
                        .tag(user)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func search() async {
        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if tab == .search && q.isEmpty { return }
        isSearching = true
        searchError = nil
        didSearch = true
        defer { isSearching = false }
        do {
            switch tab {
            case .search:
                results = try await session.userService.search(keyword: q)
            case .certified:
                results = try await session.certificationService.providers(
                    tags: q.isEmpty ? nil : q,
                    regionId: nil
                )
            }
            selected = results.first
        } catch {
            searchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            results = []
        }
    }
}

private struct UserRowView: View {
    let user: SoftUserDTO

    var body: some View {
        HStack(spacing: 12) {
            NWAvatarView(
                url: user.avatarMediaURL,
                name: user.nickname ?? "用户",
                size: 42
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(user.nickname ?? "用户").font(.body.weight(.semibold))
                HStack(spacing: 8) {
                    if let level = user.certificationLevel {
                        NWStatusChip(text: level)
                    }
                    if let score = user.creditScore {
                        Text("信用 \(score)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }
}

struct UserProfileView: View {
    let userId: String
    @Environment(AppSession.self) private var session
    @State private var user: SoftUserDTO?
    @State private var isFollowing = false
    @State private var isLoading = false
    @State private var isActing = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isLoading && user == nil {
                    ProgressView().padding(.top, 40)
                } else if let user {
                    VStack(spacing: 0) {
                        NWProfileBanner(coverURL: user.coverMediaURL, height: 150)
                        HStack(spacing: 14) {
                            NWAvatarView(
                                url: user.avatarMediaURL,
                                name: user.nickname ?? "用户",
                                size: 76
                            )
                            .overlay {
                                Circle().stroke(AppTheme.surface, lineWidth: 4)
                            }
                            .offset(y: -22)
                            .padding(.bottom, -22)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(user.nickname ?? "用户").font(.title.bold())
                                Text("信用分 \(user.creditScore ?? 60)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                NWStatusChip(text: user.certificationLevel ?? "NONE")
                            }
                            Spacer()
                            if session.currentUserId != userId {
                                Button {
                                    Task { await toggleFollow() }
                                } label: {
                                    Text(isFollowing ? "已关注" : "关注")
                                        .frame(minWidth: 72)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isActing)
                            }
                        }
                        .padding(18)
                    }
                    .ninewoodCard()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("简介").font(.headline)
                        Text(user.bio?.isEmpty == false ? user.bio! : "这个人很懒，还没有写简介")
                            .foregroundStyle(.secondary)
                        if let region = user.ipRegion ?? user.cityCode {
                            Text("地区：\(region)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("完成订单：\(user.completedOrders ?? 0)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .ninewoodCard()
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(.secondary)
                }
            }
            .padding(AppTheme.horizontalPadding)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .background(AppTheme.workspaceBackground)
        .task(id: userId) { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let dto = try await session.userService.get(id: userId)
            user = dto
            isFollowing = dto.isFollowing ?? false
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func toggleFollow() async {
        isActing = true
        defer { isActing = false }
        do {
            if isFollowing {
                try await session.userService.unfollow(id: userId)
                isFollowing = false
            } else {
                try await session.userService.follow(id: userId)
                isFollowing = true
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
