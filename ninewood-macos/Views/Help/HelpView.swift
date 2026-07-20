import SwiftUI

struct HelpView: View {
    @Environment(AppSession.self) private var session
    @State private var selectedCategory: HelpFAQ.Category = .order
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
                            Text("更新于 2025-05-20 11:30")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(selectedEntry.intro)
                                .foregroundStyle(.secondary)
                            if !selectedEntry.steps.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("结算全流程（四步）")
                                        .font(.headline)
                                    ForEach(Array(selectedEntry.steps.prefix(4).enumerated()), id: \.offset) { index, step in
                                        HStack(alignment: .top, spacing: 12) {
                                            Text("\(index + 1)")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                                .frame(width: 24, height: 24)
                                                .background(AppTheme.openStatus, in: Circle())
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(step.title)
                                                    .font(.headline)
                                                Text(step.content)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                                .padding(16)
                                .ninewoodCard()
                            }
                            if selectedEntry.id == "how-orders-work" {
                                helpSafetyCallout
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("相关链接").font(.headline)
                                    ForEach(["托管规则说明", "争议处理流程", "钱包流水查询"], id: \.self) { link in
                                        Button(link) {
                                            openHelpRelatedLink(link)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(AppTheme.primary)
                                        .font(.caption)
                                    }
                                }
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

    private func openHelpRelatedLink(_ link: String) {
        switch link {
        case "托管规则说明":
            selectedCategory = .order
            selectedEntry = HelpFAQ.entries(in: .order).first { $0.id == "escrow-fee" }
                ?? HelpFAQ.entries(in: .order).first
        case "争议处理流程":
            selectedCategory = .order
            selectedEntry = HelpFAQ.entries(in: .order).first { $0.id == "how-orders-work" }
            _ = session.navigation.navigate(to: "/orders")
        case "钱包流水查询":
            _ = session.navigation.navigate(to: "/transactions")
        default:
            break
        }
    }

    private var helpSafetyCallout: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shield.checkered")
                .font(.title3)
                .foregroundStyle(AppTheme.openStatus)
            VStack(alignment: .leading, spacing: 4) {
                Text("安全提示")
                    .font(.headline)
                Text("请在平台内完成全部交易与沟通，切勿进行线下转账或绕过托管的私下交易。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.openStatus.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(AppTheme.openStatus.opacity(0.25))
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
            intro: "「发现」展示附近可申请的需求；正式成单只走「请求接单 → 发布者接受」。",
            steps: [
                Step(title: "发现", content: "浏览列表并打开详情，点击「请求接单」进入沟通。"),
                Step(title: "正式接单", content: "仅当需求方在「我的需求」中接受申请后才会生成订单；卡池「应标 / 抢单」不是成单主链。"),
                Step(title: "卡池", content: "可查看公开需求并提交意向报价，但不会直接变成订单。"),
            ]
        ),
        Entry(
            id: "how-orders-work",
            category: .order,
            question: "订单与托管如何结算？",
            intro: "发布时托管最低保障金额；进行中按服务端付款预览预付服务费；服务者标记完成后需验收确认，平台再结算托管资金。",
            steps: [
                Step(title: "发布托管", content: "发布需求时，最低保障金额会预付至平台托管（以服务端 deposit 为准）。"),
                Step(title: "两段式成单", content: "服务方请求接单 → 需求方接受申请 → 生成订单。不要把应标/抢单当成已成交。"),
                Step(title: "进行中预付", content: "订单进入进行中后，打开付款页查看服务端分项再确认预付服务费。"),
                Step(title: "服务者完成", content: "服务者标记完成后，订单进入待验收状态。"),
                Step(title: "验收结算", content: "需求方验收确认后，平台按约定结算托管资金给服务者。"),
                Step(title: "部分完成", content: "服务方可按已完成部分提交结算金额与说明；余量与退款以服务端结算结果为准。"),
                Step(title: "取消退款", content: "取消订单时，已预付的服务费会按平台规则退回需求方。"),
            ]
        ),
        Entry(id: "escrow-fee", category: .order, question: "托管费用如何计算？", intro: "托管费用以付款预览和服务端实时计算为准。", steps: []),
        Entry(id: "preview-change", category: .order, question: "为什么预览金额会变化？", intro: "金额会随时间、数量和费用规则动态变化。", steps: []),
        Entry(id: "offline-transfer", category: .order, question: "可以线下交易或转账吗？", intro: "平台不支持绕过托管的线下充值或转账。", steps: []),
        Entry(id: "partial-settle", category: .order, question: "部分完成如何结算？", intro: "可按完成比例提交结算并由双方确认。", steps: []),
        Entry(id: "order-dispute", category: .order, question: "对订单有异议怎么办？", intro: "在验收期内发起争议并提供相关证据。", steps: []),
        Entry(id: "escrow-detail", category: .order, question: "如何查看托管资金明细？", intro: "在订单或钱包中查看托管与结算记录。", steps: []),
        Entry(id: "payer-cancel", category: .order, question: "付款方可以取消订单吗？", intro: "取消能力由当前订单状态和服务端规则决定。", steps: []),
        Entry(id: "natural-loop", category: .order, question: "什么是自然回？", intro: "自然回提供可验证、可复用的自动化结果。", steps: []),
        Entry(id: "refund", category: .order, question: "如何申请退款？", intro: "符合条件时可在订单详情中发起退款。", steps: []),
        Entry(id: "escrow-timeout", category: .order, question: "托管超时会怎样？", intro: "平台会依据订单状态和规则自动处理。", steps: []),
        Entry(id: "export-proof", category: .order, question: "如何导出订单凭证？", intro: "订单完成后可下载交易与结算凭证。", steps: []),
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
            intro: "请求接单后可在「消息」沟通；初期圈子为私人圈，需邀请码加入。",
            steps: [
                Step(title: "消息", content: "支持实时推送（在线时无需手动刷新）。"),
                Step(title: "圈子", content: "在「圈子」创建私人圈，或使用邀请码加入。"),
            ]
        ),
        Entry(
            id: "what-is-loop",
            category: .feature,
            question: "「回」是什么？",
            intro: "「回」是九木的自然回路能力：用人可提交的输入，调用接口直接拿回结果。",
            steps: [
                Step(title: "入口", content: "侧栏「回」：发现回寻找地回，我的回查看运行记录。"),
                Step(title: "运行", content: "选择回路并提交输入即可查看结果。"),
            ]
        ),
    ]
}
