import SwiftUI

struct HelpView: View {
    @State private var selectedCategory: HelpFAQ.Category = HelpFAQ.Category.categories[0]
    @State private var selectedEntry: HelpFAQ.Entry?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                NWPaneCaption(text: "常见问题")
                List(selection: $selectedCategory) {
                    ForEach(HelpFAQ.Category.categories) { category in
                        Label(category.title, systemImage: category.systemImage)
                            .tag(category)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .paneColumn(minWidth: 180, idealWidth: 200)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                Text(selectedCategory.title)
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                List(HelpFAQ.entries(in: selectedCategory), selection: $selectedEntry) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.question).font(.body.weight(.semibold))
                        Text(entry.intro)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .tag(Optional(entry))
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .paneColumn(minWidth: 280, idealWidth: 320)

            Divider()

            Group {
                if let selectedEntry {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(selectedEntry.question)
                                .font(.title2.bold())
                            Text(selectedEntry.intro)
                                .foregroundStyle(.secondary)
                            if !selectedEntry.steps.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(Array(selectedEntry.steps.enumerated()), id: \.offset) { index, step in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("\(index + 1). \(step.title)")
                                                .font(.headline)
                                            Text(step.content)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(16)
                                .ninewoodCard()
                            }
                        }
                        .padding(AppTheme.horizontalPadding)
                        .frame(maxWidth: 640, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(AppTheme.workspaceBackground)
                } else {
                    NWDetailPlaceholder(
                        title: "帮助中心",
                        systemImage: "questionmark.circle",
                        message: "选择左侧分类与问题"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("帮助")
        .onAppear {
            if selectedEntry == nil {
                selectedEntry = HelpFAQ.entries(in: selectedCategory).first
            }
        }
        .onChange(of: selectedCategory) { _, newValue in
            selectedEntry = HelpFAQ.entries(in: newValue).first
        }
    }
}

enum HelpFAQ {
    enum Category: String, CaseIterable, Identifiable, Hashable {
        case demand
        case discover
        case order
        case cert
        case social
        case feature

        var id: String { rawValue }

        var title: String {
            switch self {
            case .demand: "发布与管理"
            case .discover: "发现与匹配"
            case .order: "订单与支付"
            case .cert: "认证与信用"
            case .social: "沟通与社区"
            case .feature: "平台特色"
            }
        }

        var systemImage: String {
            switch self {
            case .demand: "doc.badge.plus"
            case .discover: "sparkles"
            case .order: "checklist"
            case .cert: "checkmark.shield"
            case .social: "bubble.left.and.bubble.right"
            case .feature: "square.stack.3d.up"
            }
        }

        static let categories: [Category] = [.demand, .discover, .order, .cert, .social, .feature]
    }

    struct Step: Hashable {
        let title: String
        let content: String
    }

    struct Entry: Identifiable, Hashable {
        let id: String
        let category: Category
        let question: String
        let intro: String
        let steps: [Step]
    }

    static func entries(in category: Category) -> [Entry] {
        all.filter { $0.category == category }
    }

    static let all: [Entry] = [
        Entry(
            id: "how-to-publish",
            category: .demand,
            question: "如何发布需求？",
            intro: "在侧栏进入「发布」，填写标题、期望效果与最低保障金额，选择标签与地区后提交。",
            steps: [
                Step(title: "进入发布", content: "点击左侧「发布」。"),
                Step(title: "填写信息", content: "标题与期望效果是验收依据，请写清楚。"),
                Step(title: "标签与地区", content: "线下需求需选择地区；标签有助于匹配认证服务者。"),
                Step(title: "托管发布", content: "最低保障金额会预付至平台托管。"),
            ]
        ),
        Entry(
            id: "how-to-discover",
            category: .discover,
            question: "如何发现附近需求？",
            intro: "「发现」展示附近可申请的需求；「卡池」汇总进行中的需求。",
            steps: [
                Step(title: "发现", content: "浏览列表并打开详情，可请求接单。"),
                Step(title: "卡池", content: "查看可竞价 / 可接的公开需求池。"),
            ]
        ),
        Entry(
            id: "how-orders-work",
            category: .order,
            question: "订单与托管如何结算？",
            intro: "发布时托管最低保障金额；进行中预付 5% 服务费；服务者标记完成后需验收确认，平台再结算托管资金。",
            steps: [
                Step(title: "发布托管", content: "发布需求时，最低保障金额（minPrice）会预付至平台托管。"),
                Step(title: "进行中预付", content: "订单进入进行中后，平台会预付 5% 服务费至托管账户。"),
                Step(title: "服务者完成", content: "服务者标记完成后，订单进入待验收状态。"),
                Step(title: "验收结算", content: "需求方验收确认后，平台按约定结算托管资金给服务者。"),
                Step(title: "部分完成", content: "若仅部分完成，可按 partial 比例结算，剩余托管退回。"),
                Step(title: "取消退款", content: "取消订单时，已预付的服务费会退回需求方。"),
            ]
        ),
        Entry(
            id: "how-cert",
            category: .cert,
            question: "如何成为认证服务者？",
            intro: "在「认证」选择技能标签与地区提交申请，完成订单与信用达标后可升级。",
            steps: [
                Step(title: "提交申请", content: "进入认证中心选择擅长标签。"),
                Step(title: "升级", content: "满足条件后可点击升级等级。"),
            ]
        ),
        Entry(
            id: "how-messages",
            category: .social,
            question: "如何沟通与进圈子？",
            intro: "请求接单后可在「消息」沟通；「圈子」可浏览公开圈并加入。",
            steps: [
                Step(title: "消息", content: "支持实时推送（在线时无需手动刷新）。"),
                Step(title: "圈子", content: "公开列表加入，或使用邀请码。"),
            ]
        ),
        Entry(
            id: "what-is-loop",
            category: .feature,
            question: "「回」是什么？",
            intro: "「回」是九木的自然回路能力：用人可提交的输入，调用接口直接拿回结果。",
            steps: [
                Step(title: "入口", content: "侧栏「回」或发现页「可用地回」。"),
                Step(title: "运行", content: "选择回路并提交输入即可查看结果。"),
            ]
        ),
    ]
}
