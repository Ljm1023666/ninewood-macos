import AppKit
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
    private let previewUsers: [SoftUserDTO]?

    init(previewUsers: [SoftUserDTO]? = nil) {
        self.previewUsers = previewUsers
        _results = State(initialValue: previewUsers ?? [])
        _selected = State(initialValue: previewUsers?.first)
        _didSearch = State(initialValue: previewUsers != nil)
        _tab = State(initialValue: previewUsers != nil ? .certified : .search)
    }

    var body: some View {
        // 08 找人：始终使用渲染图工作台；生产环境从 API 拉同一视觉结构的数据
        FindPeopleReferencePreview(useStaticFixtures: previewUsers != nil)
            .navigationTitle("找人")
    }

    private var liveBody: some View {
        HStack(spacing: 0) {
            listPane
                .paneColumn(minWidth: 430, idealWidth: 560)

            Divider()

            Group {
                if let selected {
                    UserProfileView(userId: selected.id, previewUser: nil)
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
                    Swift.Task { await search() }
                }
                Button {
                    Swift.Task { await search() }
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
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(results) { user in
                            Button {
                                selected = user
                            } label: {
                                UserRowView(user: user, isSelected: selected?.id == user.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                }
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

// MARK: - Design preview (08)

private struct FindPeopleReferencePreview: View {
    enum Tab: String, CaseIterable, Identifiable {
        case search = "搜索"
        case certified = "认证服务者"
        var id: String { rawValue }
    }

    enum LayoutMode: String, CaseIterable {
        case grid
        case list
    }

    var useStaticFixtures = false

    @Environment(AppSession.self) private var session
    @State private var tab: Tab = .certified
    @State private var keyword = ""
    @State private var people: [FindPeopleDesignPerson]
    @State private var selectedID: String
    @State private var layout: LayoutMode = .grid
    @State private var isFollowing = false
    @State private var showDetail = true
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var followBusy = false
    @State private var filterTag: String?
    @State private var filterRegionLabel: String = "全国"
    @State private var filterRegionId: Int?
    @State private var availableTags: [String] = []
    @State private var availableRegions: [RegionDTO] = []

    init(useStaticFixtures: Bool = false) {
        self.useStaticFixtures = useStaticFixtures
        if useStaticFixtures {
            let seed = FindPeopleDesignFixtures.people
            _people = State(initialValue: seed)
            _selectedID = State(initialValue: seed.first?.id ?? "")
        } else {
            _people = State(initialValue: [])
            _selectedID = State(initialValue: "")
        }
    }

    private var filtered: [FindPeopleDesignPerson] {
        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return people }
        return people.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.title.localizedCaseInsensitiveContains(q)
                || $0.tags.joined(separator: " ").localizedCaseInsensitiveContains(q)
                || $0.bio.localizedCaseInsensitiveContains(q)
        }
    }

    private var selected: FindPeopleDesignPerson? {
        filtered.first(where: { $0.id == selectedID }) ?? filtered.first
    }

    var body: some View {
        previewContent
            .background(AppTheme.surface)
            .onChange(of: tab) { _, _ in
                keyword = ""
                selectedID = people.first?.id ?? ""
                showDetail = true
                if !useStaticFixtures {
                    Task { await loadLivePeople() }
                }
            }
            .onChange(of: keyword) { _, newValue in
                // 清空关键词时恢复种子/认证列表；输入中仍可本地滤当前结果
                guard !useStaticFixtures else { return }
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Task { await loadLivePeople() }
                }
            }
            .onChange(of: selectedID) { _, newID in
                guard !useStaticFixtures, !newID.isEmpty else { return }
                followBusy = false
            }
            .onAppear {
                guard !useStaticFixtures else { return }
                Swift.Task {
                    await loadLivePeople()
                    await refreshFollowingState()
                }
            }
    }

    private var previewContent: some View {
        HStack(spacing: 0) {
            listPane
                .frame(minWidth: 520, idealWidth: 640, maxWidth: .infinity)

            if showDetail, let selected {
                Divider()
                FindPeopleProfileDetail(
                    person: selected,
                    isFollowing: $isFollowing,
                    onClose: { showDetail = false },
                    onToggleFollow: followAction(for: selected.id),
                    onSendMessage: messageAction(for: selected.id),
                    followBusy: followBusy
                )
                .frame(width: 360)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private func loadLivePeople() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            // 按服务端返回顺序展示，不做种子账号硬置顶（产品原则：曝光不可人为加权）。
            let providers = try await session.certificationService.providers(page: 1)
            await applyPeople(FindPeopleDesignFixtures.mergeLiveHonest(providers))
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 回车提交：走服务端搜索（不再只滤本地种子）
    private func searchPeople() async {
        guard !useStaticFixtures else { return }
        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            await loadLivePeople()
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let rows: [SoftUserDTO]
            switch tab {
            case .search:
                rows = try await session.userService.search(keyword: q)
            case .certified:
                rows = try await session.certificationService.providers(
                    tags: q,
                    regionId: nil
                )
            }
            await applyPeople(FindPeopleDesignFixtures.mergeLiveHonest(rows))
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            people = []
        }
    }

    private func applyPeople(_ mapped: [FindPeopleDesignPerson]) async {
        people = mapped
        if people.contains(where: { $0.id == selectedID }) == false {
            selectedID = people.first?.id ?? selectedID
        }
        await refreshFollowingState()
    }

    private func refreshFollowingState() async {
        guard !useStaticFixtures, let selected else {
            isFollowing = false
            return
        }
        isFollowing = people.first(where: { $0.id == selected.id })?.isFollowing ?? false
        // 再拉一次资料确认关注态
        if let dto = try? await session.userService.get(id: selected.id) {
            isFollowing = dto.isFollowing ?? isFollowing
        }
    }

    private func followAction(for userID: String) -> (() async -> Void)? {
        guard !useStaticFixtures else { return nil }
        return { await toggleFollow(userID: userID) }
    }

    private func messageAction(for userID: String) -> (() -> Void)? {
        guard !useStaticFixtures else { return nil }
        return {
            session.navigation.openDirectMessage(peerID: userID)
        }
    }

    private func toggleFollow(userID: String) async {
        guard !followBusy else { return }
        followBusy = true
        defer { followBusy = false }
        do {
            if isFollowing {
                try await session.userService.unfollow(id: userID)
                isFollowing = false
            } else {
                try await session.userService.follow(id: userID)
                isFollowing = true
            }
            if let idx = people.firstIndex(where: { $0.id == userID }) {
                people[idx].isFollowing = isFollowing
            }
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Tab.allCases) { item in
                    Button {
                        tab = item
                    } label: {
                        VStack(spacing: 8) {
                            Text(item.rawValue)
                                .font(.system(size: 14, weight: tab == item ? .semibold : .medium))
                                .foregroundStyle(tab == item ? AppTheme.primary : AppTheme.secondaryLabel)
                            Rectangle()
                                .fill(tab == item ? AppTheme.primary : SwiftUI.Color.clear)
                                .frame(height: 2)
                        }
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 20)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)

            NWSearchBar(
                text: $keyword,
                placeholder: "搜索姓名、技能、经验或关键词"
            ) {
                Task { await searchPeople() }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            filterRow
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

            resultsHeader
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            if filtered.isEmpty {
                NWEmptyState(
                    title: "没有找到认证服务者",
                    systemImage: "person.slash",
                    message: "换个关键词或筛选条件试试"
                )
                Spacer(minLength: 0)
            } else if layout == .grid {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(filtered) { person in
                            Button {
                                selectedID = person.id
                                showDetail = true
                                isFollowing = person.isFollowing
                            } label: {
                                FindPeopleProviderCard(
                                    person: person,
                                    isSelected: person.id == selected?.id && showDetail
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { person in
                            Button {
                                selectedID = person.id
                                showDetail = true
                                isFollowing = person.isFollowing
                            } label: {
                                FindPeopleProviderCard(
                                    person: person,
                                    isSelected: person.id == selected?.id && showDetail,
                                    compact: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppTheme.surface)
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            Menu {
                Button("全部标签") { filterTag = nil }
                ForEach(availableTags.isEmpty ? FindPeopleDesignFixtures.commonTags : availableTags, id: \.self) { tag in
                    Button(tag) { filterTag = tag }
                }
            } label: {
                filterChip(filterTag ?? "全部标签", systemImage: "chevron.down")
            }
            .menuStyle(.borderlessButton)

            Menu {
                Button("全国") {
                    filterRegionId = nil
                    filterRegionLabel = "全国"
                }
                ForEach(availableRegions) { region in
                    Button(region.name ?? "\(region.id)") {
                        filterRegionId = region.id
                        filterRegionLabel = region.name ?? "\(region.id)"
                    }
                }
            } label: {
                filterChip(filterRegionLabel, systemImage: "chevron.down")
            }
            .menuStyle(.borderlessButton)

            filterChip("服务方式", systemImage: "chevron.down")
            Spacer(minLength: 8)
            Button("重置") {
                filterTag = nil
                filterRegionId = nil
                filterRegionLabel = "全国"
                keyword = ""
                if !useStaticFixtures {
                    Task { await loadLivePeople() }
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(AppTheme.secondaryLabel)
            Button {
                guard !useStaticFixtures else { return }
                Task { await applyFilters() }
            } label: {
                Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .task {
            guard !useStaticFixtures, availableTags.isEmpty else { return }
            availableTags = ((try? await session.tagService.list()) ?? []).map(\.name)
            availableRegions = (try? await session.regionService.children()) ?? []
        }
    }

    private func applyFilters() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let tagsParam = filterTag
            let rows: [SoftUserDTO]
            if tab == .search, let tag = tagsParam, !tag.isEmpty {
                rows = try await session.userService.searchByTags(tag, regionId: filterRegionId)
            } else {
                rows = try await session.certificationService.providers(
                    tags: tagsParam,
                    regionId: filterRegionId
                )
            }
            await applyPeople(FindPeopleDesignFixtures.mergeLiveHonest(rows))
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func filterChip(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(AppTheme.onSurface)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
        }
    }

    private var resultsHeader: some View {
        HStack(spacing: 10) {
            Text("共 \(filtered.count) 位认证服务者")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.secondaryLabel)
            Spacer()
            HStack(spacing: 4) {
                Text("默认排序")
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(AppTheme.onSurface)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
            }

            HStack(spacing: 0) {
                layoutButton(.grid, icon: "square.grid.2x2")
                layoutButton(.list, icon: "list.bullet")
            }
            .padding(2)
            .background(AppTheme.fill.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func layoutButton(_ mode: LayoutMode, icon: String) -> some View {
        Button {
            layout = mode
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(layout == mode ? AppTheme.primary : AppTheme.secondaryLabel)
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(layout == mode ? AppTheme.surface : SwiftUI.Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct FindPeopleProviderCard: View {
    let person: FindPeopleDesignPerson
    var isSelected = false
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                FindPeopleAvatar(
                    name: person.name,
                    asset: person.avatarAsset,
                    url: person.avatarURL,
                    size: compact ? 44 : 48
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(person.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.onSurface)
                    Text(person.title)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .lineLimit(1)
                    Text(person.badge)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.openStatus)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppTheme.openStatus.opacity(0.12), in: Capsule(style: .continuous))
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                ForEach(person.tags.prefix(3), id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                        }
                }
            }

            Label(person.location, systemImage: "mappin.and.ellipse")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryLabel)

            HStack(spacing: 12) {
                Text("完成 \(person.orders) 单")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.urgent)
                    Text(person.rating)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.onSurface)
                }
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Circle()
                        .fill(person.available ? AppTheme.openStatus : AppTheme.urgent)
                        .frame(width: 6, height: 6)
                    Text(person.available ? "可接单" : "忙碌中")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(person.available ? AppTheme.openStatus : AppTheme.urgent)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? AppTheme.softPrimary : AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSelected ? AppTheme.primary.opacity(0.55) : AppTheme.outlineVariant,
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
    }
}

private struct FindPeopleProfileDetail: View {
    let person: FindPeopleDesignPerson
    @Binding var isFollowing: Bool
    var onClose: () -> Void
    var onToggleFollow: (() async -> Void)? = nil
    var onSendMessage: (() -> Void)? = nil
    var followBusy = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .frame(width: 28, height: 28)
                        .background(AppTheme.fill.opacity(0.7), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    bioSection
                    reliabilitySection
                    tagsSection
                    experienceSection
                    availabilitySection
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }

            actionBar
        }
        .background(AppTheme.surface)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                FindPeopleAvatar(name: person.name, asset: person.avatarAsset, url: person.avatarURL, size: 72)
                VStack(alignment: .leading, spacing: 6) {
                    Text(person.name)
                        .font(.system(size: 20, weight: .bold))
                    Text(person.title)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.secondaryLabel)
                    Text(person.badge)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.openStatus)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppTheme.openStatus.opacity(0.12), in: Capsule(style: .continuous))
                }
            }
            Label(person.location, systemImage: "mappin.and.ellipse")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondaryLabel)
        }
    }

    private var bioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("个人简介")
                .font(.system(size: 14, weight: .semibold))
            Text(person.bio)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.secondaryLabel)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reliabilitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("可靠性数据")
                .font(.system(size: 14, weight: .semibold))
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                metric(icon: "checkmark.circle", tint: AppTheme.primary, value: "\(person.orders)", title: "完成订单")
                metric(icon: "clock", tint: AppTheme.openStatus, value: person.onTime, title: "按时交付")
                metric(icon: "star.fill", tint: AppTheme.urgent, value: person.rating, title: "平均评分")
                metric(icon: "arrow.triangle.2.circlepath", tint: AppTheme.secondary, value: person.repurchase, title: "复购率")
            }
        }
    }

    private func metric(icon: String, tint: Color, value: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .bold))
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(AppTheme.surfaceLow, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("服务标签")
                .font(.system(size: 14, weight: .semibold))
            HStack(spacing: 8) {
                ForEach(person.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(AppTheme.surfaceLow, in: Capsule(style: .continuous))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
                        }
                }
            }
        }
    }

    private var experienceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("近期匿名经验")
                .font(.system(size: 14, weight: .semibold))
            ForEach(person.experiences) { item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(item.tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(item.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var availabilitySection: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Circle()
                    .fill(person.available ? AppTheme.openStatus : AppTheme.urgent)
                    .frame(width: 7, height: 7)
                Text(person.available ? "可接单" : "忙碌中")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(person.available ? AppTheme.openStatus : AppTheme.urgent)
            }
            Text(person.remaining)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondaryLabel)
            Spacer(minLength: 0)
            Text(person.response)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondaryLabel)
        }
        .padding(12)
        .background(AppTheme.surfaceLow, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                onSendMessage?()
            } label: {
                Label("发消息", systemImage: "bubble.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(onSendMessage == nil)

            Button {
                if let onToggleFollow {
                    Swift.Task { await onToggleFollow() }
                } else {
                    isFollowing.toggle()
                }
            } label: {
                Text(followBusy ? "…" : (isFollowing ? "已关注" : "+ 关注"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(AppTheme.primary.opacity(0.7), lineWidth: 1.2)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppTheme.surface)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

private struct FindPeopleAvatar: View {
    let name: String
    let asset: String?
    var url: URL? = nil
    let size: CGFloat

    var body: some View {
        Group {
            if let url {
                NWAvatarView(url: url, name: name, size: size)
            } else if let asset, NSImage(named: asset) != nil {
                Image(asset)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                NWAvatarView(url: nil, name: name, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(AppTheme.outlineVariant.opacity(0.5), lineWidth: 0.5)
        }
    }
}

// MARK: - Fixtures

private struct FindPeopleDesignPerson: Identifiable, Hashable {
    let id: String
    let name: String
    let title: String
    let badge: String
    let tags: [String]
    let location: String
    let orders: Int
    let rating: String
    let available: Bool
    let bio: String
    let onTime: String
    let repurchase: String
    let remaining: String
    let response: String
    let avatarAsset: String?
    var avatarURL: URL? = nil
    let experiences: [FindPeopleExperience]
    var isFollowing: Bool = false
}

private struct FindPeopleExperience: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let tint: SwiftUI.Color

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: FindPeopleExperience, rhs: FindPeopleExperience) -> Bool {
        lhs.id == rhs.id
    }
}

private enum FindPeopleDesignFixtures {
    static let totalCount = 238

    /// 与 seed-macos-find-people-preview.sql 中的固定 UUID 对齐
    static let previewUserIDs: [String] = [
        "00000008-0001-4000-8000-000000000001",
        "00000008-0002-4000-8000-000000000002",
        "00000008-0003-4000-8000-000000000003",
        "00000008-0004-4000-8000-000000000004",
        "00000008-0005-4000-8000-000000000005",
        "00000008-0006-4000-8000-000000000006",
        "00000008-0007-4000-8000-000000000007",
        "00000008-0008-4000-8000-000000000008",
    ]

    static let commonTags: [String] = [
        "产品设计", "用户研究", "视觉设计", "数据分析", "内容设计", "全栈开发",
    ]

    static let people: [FindPeopleDesignPerson] = [
        FindPeopleDesignPerson(
            id: "fp-1",
            name: "陈知远",
            title: "产品策略与用户研究",
            badge: "已认证 · L5",
            tags: ["产品策略", "用户研究", "数据分析"],
            location: "上海 · 可远程 / 到场",
            orders: 128,
            rating: "4.9",
            available: true,
            bio: "8 年互联网产品经验，擅长把模糊目标拆成可验证路径。近三年以匿名协作完成多轮产品定位、用户研究与增长实验，重视过程透明与可复用交付。",
            onTime: "100%",
            repurchase: "98%",
            remaining: "本周剩余 3 天",
            response: "平均响应 2 小时内",
            avatarAsset: "AvatarChenShu",
            experiences: [
                FindPeopleExperience(
                    id: "e1",
                    title: "消费品牌 App 用户增长策略",
                    detail: "通过用户分层与关键路径优化，推动 DAU 提升 35%，次日留存提升 12%。",
                    icon: "chart.line.uptrend.xyaxis",
                    tint: AppTheme.primary
                ),
                FindPeopleExperience(
                    id: "e2",
                    title: "企业 SaaS 产品定位与 MVP",
                    detail: "梳理价值主张与目标客户，完成市场验证并落地可演示 MVP。",
                    icon: "building.2",
                    tint: SwiftUI.Color(red: 0.35, green: 0.45, blue: 0.85)
                ),
                FindPeopleExperience(
                    id: "e3",
                    title: "研究洞察结构化交付",
                    detail: "将访谈材料沉淀为决策可读的洞察报告与优先级清单。",
                    icon: "chart.bar",
                    tint: AppTheme.openStatus
                )
            ]
        ),
        FindPeopleDesignPerson(
            id: "fp-2",
            name: "周屿",
            title: "品牌视觉与产品图标",
            badge: "已认证 · L4",
            tags: ["品牌升级", "图标设计", "多端适配"],
            location: "杭州 · 可远程",
            orders: 46,
            rating: "4.9",
            available: true,
            bio: "产品与品牌视觉设计，重视过程透明与可靠交付。擅长从风格探索到多端图标与规范落地。",
            onTime: "100%",
            repurchase: "96%",
            remaining: "本周剩余 2 天",
            response: "平均响应 3 小时内",
            avatarAsset: "AvatarFangZhou",
            experiences: [
                FindPeopleExperience(
                    id: "e1",
                    title: "工具类产品图标体系",
                    detail: "建立多尺寸导出规范，完成一次集中修改与交付。",
                    icon: "paintbrush",
                    tint: AppTheme.primary
                ),
                FindPeopleExperience(
                    id: "e2",
                    title: "品牌视觉升级",
                    detail: "统一图形语言与使用规范，支撑多端一致性。",
                    icon: "square.stack.3d.up",
                    tint: SwiftUI.Color(red: 0.35, green: 0.45, blue: 0.85)
                )
            ]
        ),
        FindPeopleDesignPerson(
            id: "fp-3",
            name: "程野",
            title: "用户研究与内容整理",
            badge: "已认证 · L3",
            tags: ["用户访谈", "研究报告", "内容整理"],
            location: "北京 · 可远程 / 到场",
            orders: 31,
            rating: "4.8",
            available: false,
            bio: "用户研究与内容整理，擅长把访谈材料沉淀为可执行洞察。",
            onTime: "98%",
            repurchase: "94%",
            remaining: "约 3 天后有空",
            response: "平均响应 4 小时内",
            avatarAsset: "AvatarXuYan",
            experiences: [
                FindPeopleExperience(
                    id: "e1",
                    title: "早期产品访谈验证",
                    detail: "完成提纲、执行与结构化洞察，支撑迭代方向。",
                    icon: "person.2",
                    tint: AppTheme.primary
                )
            ]
        ),
        FindPeopleDesignPerson(
            id: "fp-4",
            name: "乔安",
            title: "数据分析与指标设计",
            badge: "已认证 · L3",
            tags: ["数据分析", "指标设计", "研究报告"],
            location: "深圳 · 可远程",
            orders: 19,
            rating: "4.7",
            available: true,
            bio: "数据分析和研究报告，关注指标口径与可读表达。",
            onTime: "97%",
            repurchase: "92%",
            remaining: "本周剩余 4 天",
            response: "平均响应 2 小时内",
            avatarAsset: "AvatarZhangMo",
            experiences: [
                FindPeopleExperience(
                    id: "e1",
                    title: "核心指标口径梳理",
                    detail: "统一关键指标定义，输出可读周报模板。",
                    icon: "chart.bar.doc.horizontal",
                    tint: AppTheme.openStatus
                )
            ]
        ),
        FindPeopleDesignPerson(
            id: "fp-5",
            name: "林夏",
            title: "产品设计与交互",
            badge: "已认证 · L4",
            tags: ["产品设计", "交互设计", "原型"],
            location: "上海 · 可远程",
            orders: 67,
            rating: "4.9",
            available: true,
            bio: "产品设计与交互，擅长把复杂流程做成清晰可演示的原型与规范。",
            onTime: "99%",
            repurchase: "95%",
            remaining: "本周剩余 1 天",
            response: "平均响应 1 小时内",
            avatarAsset: "AvatarLinXia",
            experiences: [
                FindPeopleExperience(
                    id: "e1",
                    title: "B 端工作台信息架构",
                    detail: "重构导航与任务流，缩短关键路径并提升完成率。",
                    icon: "rectangle.3.group",
                    tint: AppTheme.primary
                )
            ]
        ),
        FindPeopleDesignPerson(
            id: "fp-6",
            name: "许言",
            title: "内容策略与写作",
            badge: "已认证 · L3",
            tags: ["内容策略", "文案", "品牌叙事"],
            location: "成都 · 可远程",
            orders: 42,
            rating: "4.8",
            available: true,
            bio: "内容策略与品牌叙事，帮助产品把价值讲清楚。",
            onTime: "100%",
            repurchase: "93%",
            remaining: "本周剩余 5 天",
            response: "平均响应 3 小时内",
            avatarAsset: "AvatarXuYan",
            experiences: [
                FindPeopleExperience(
                    id: "e1",
                    title: "产品官网叙事重构",
                    detail: "统一卖点表达与案例结构，提升询盘转化。",
                    icon: "text.book.closed",
                    tint: SwiftUI.Color(red: 0.35, green: 0.45, blue: 0.85)
                )
            ]
        ),
        FindPeopleDesignPerson(
            id: "fp-7",
            name: "方舟",
            title: "全栈开发与交付",
            badge: "已认证 · L4",
            tags: ["全栈开发", "接口联调", "上线交付"],
            location: "广州 · 可远程 / 到场",
            orders: 58,
            rating: "4.8",
            available: false,
            bio: "全栈开发与上线交付，重视可维护性与交接文档。",
            onTime: "97%",
            repurchase: "91%",
            remaining: "约 5 天后有空",
            response: "平均响应 5 小时内",
            avatarAsset: "AvatarFangZhou",
            experiences: [
                FindPeopleExperience(
                    id: "e1",
                    title: "协作平台 MVP 交付",
                    detail: "两周完成核心链路联调与上线，附运维清单。",
                    icon: "chevron.left.forwardslash.chevron.right",
                    tint: AppTheme.openStatus
                )
            ]
        ),
        FindPeopleDesignPerson(
            id: "fp-8",
            name: "张默",
            title: "增长实验与渠道",
            badge: "已认证 · L3",
            tags: ["增长实验", "渠道投放", "留存"],
            location: "杭州 · 可远程",
            orders: 27,
            rating: "4.7",
            available: true,
            bio: "增长实验与渠道投放，用小步快跑验证获客与留存假设。",
            onTime: "96%",
            repurchase: "90%",
            remaining: "本周剩余 2 天",
            response: "平均响应 4 小时内",
            avatarAsset: "AvatarZhangMo",
            experiences: [
                FindPeopleExperience(
                    id: "e1",
                    title: "冷启动渠道实验",
                    detail: "搭建实验看板，两周内找到可复制获客组合。",
                    icon: "flame",
                    tint: AppTheme.urgent
                )
            ]
        )
    ]

    /// Live 映射：只用 SoftUserDTO 真实字段，不发明评分/经验/头像资产。
    static func mergeLiveHonest(_ rows: [SoftUserDTO]) -> [FindPeopleDesignPerson] {
        rows.map { row in
            let tags = row.resolvedServiceTags
            let level = row.certificationLevel ?? "BASIC"
            let city = row.ipRegion ?? row.cityCode ?? "全国"
            let title: String = {
                if let first = tags.first, !first.isEmpty { return first }
                if let bio = row.bio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
                    return bio.components(separatedBy: CharacterSet(charactersIn: "，。,.")).first ?? bio
                }
                return "认证服务者"
            }()
            let orders = row.totalCompleted ?? row.completedOrders ?? 0
            return FindPeopleDesignPerson(
                id: row.id,
                name: row.nickname ?? "用户",
                title: title,
                badge: "已认证 · \(level)",
                tags: tags,
                location: city,
                orders: orders,
                rating: row.displayRating ?? "—",
                available: true,
                bio: {
                    let bio = row.bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return bio.isEmpty ? "暂无简介" : bio
                }(),
                onTime: orders > 0 ? "按时交付" : "—",
                repurchase: row.avgRating.map { $0 >= 4.8 ? "复购高" : "口碑稳定" } ?? "—",
                remaining: "可约档",
                response: "平均响应及时",
                avatarAsset: nil,
                avatarURL: row.avatarMediaURL,
                experiences: [],
                isFollowing: row.isFollowing ?? false
            )
        }
    }
}

// MARK: - Live list / profile

private struct UserRowView: View {
    let user: SoftUserDTO
    var isSelected = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NWAvatarView(
                url: user.avatarMediaURL,
                name: user.nickname ?? "用户",
                size: 48
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
                Text(user.bio?.isEmpty == false ? user.bio! : "认证服务者")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Label(user.ipRegion ?? user.cityCode ?? "全国", systemImage: "mappin.and.ellipse")
                    Spacer(minLength: 0)
                    Text("完成 \(user.completedOrders ?? 0) 单")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .background(isSelected ? AppTheme.primary.opacity(0.10) : AppTheme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(isSelected ? AppTheme.primary : AppTheme.outlineVariant, lineWidth: isSelected ? 1.5 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }
}

struct UserProfileView: View {
    let userId: String
    let previewUser: SoftUserDTO?
    @Environment(AppSession.self) private var session
    @State private var user: SoftUserDTO?
    @State private var isFollowing = false
    @State private var isLoading = false
    @State private var isActing = false
    @State private var errorMessage: String?

    init(userId: String, previewUser: SoftUserDTO? = nil) {
        self.userId = userId
        self.previewUser = previewUser
        _user = State(initialValue: previewUser)
        _isFollowing = State(initialValue: previewUser?.isFollowing ?? false)
    }

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
                                    Swift.Task { await toggleFollow() }
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

                    HStack(spacing: 12) {
                        metric(title: "完成订单", value: "\(user.completedOrders ?? 0)", icon: "checkmark.circle")
                        metric(title: "按时交付", value: "100%", icon: "clock")
                        metric(title: "信用评分", value: "\(user.creditScore ?? 60)", icon: "star")
                        metric(title: "回复率", value: "98%", icon: "arrow.clockwise")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("服务标签").font(.headline)
                        HStack(spacing: 8) {
                            NWStatusChip(text: "产品策略")
                            NWStatusChip(text: "用户研究")
                            NWStatusChip(text: "数据分析")
                        }
                    }
                    .padding(16)
                    .ninewoodCard()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("近期匿名经验").font(.headline)
                        experience("消费品牌 App 用户增长策略", "通过用户分层与关键路径优化，推动增长与留存。", "chart.line.uptrend.xyaxis")
                        Divider()
                        experience("企业 SaaS 产品定位与 MVP", "梳理价值主张，完成市场与用户验证。", "square.stack.3d.up")
                    }
                    .padding(16)
                    .ninewoodCard()
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(.secondary)
                }
            }
            .padding(AppTheme.horizontalPadding)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .background(AppTheme.workspaceBackground)
        .task(id: userId) { await load() }
    }

    private func metric(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(AppTheme.primary)
            Text(value).font(.title3.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninewoodCard()
    }

    private func experience(_ title: String, _ detail: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppTheme.primary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func load() async {
        if let previewUser {
            user = previewUser
            isFollowing = previewUser.isFollowing ?? false
            return
        }
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
