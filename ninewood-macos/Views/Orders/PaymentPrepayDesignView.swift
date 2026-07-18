import SwiftUI

// MARK: - Design preview (page 26)

/// 像素级对齐 `docs/ui-renderings/26-payment-sheet.png`：侧栏 + 订单详情底图 +「确认预付」弹层。
/// 纯前端静态稿，不请求后端。
struct PaymentPrepayDesignPreview: View {
    var body: some View {
        ZStack {
            PaymentPrepayOrderBackdrop()
            Color.black.opacity(0.28)
                .ignoresSafeArea()
            PaymentPrepayModal(
                model: .constant(.designFixture),
                showsRetryBanner: true,
                onCancel: {},
                onConfirm: {},
                onRetryPreview: {},
                onClose: {}
            )
            .frame(width: 520)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 1100, minHeight: 780)
    }
}

// MARK: - Modal model

struct PaymentPrepayModalModel: Equatable {
    var orderCode: String
    var demandTitle: String
    var requesterName: String
    var providerName: String
    var agreedAmount: Decimal
    var escrowAmount: Decimal
    var feeRate: Decimal
    var serviceFee: Decimal
    var balance: Decimal
    var ruleVersion: String
    var agreedChecked: Bool

    var balanceAfterPay: Decimal { balance - serviceFee }

    static let designFixture = PaymentPrepayModalModel(
        orderCode: "SO-202607-0117",
        demandTitle: "产品需求与用户反馈整理",
        requesterName: "林一",
        providerName: "思远工作室",
        agreedAmount: 600,
        escrowAmount: 600,
        feeRate: Decimal(string: "0.05")!,
        serviceFee: 30,
        balance: 1000,
        ruleVersion: "2026-07",
        agreedChecked: true
    )
}

// MARK: - Confirm prepay modal

struct PaymentPrepayModal: View {
    @Binding var model: PaymentPrepayModalModel
    var showsRetryBanner: Bool = false
    var isLoadingPreview: Bool = false
    var isConfirming: Bool = false
    var confirmEnabled: Bool = true
    var onCancel: () -> Void
    var onConfirm: () -> Void
    var onRetryPreview: () -> Void = {}
    var onClose: () -> Void

    private var feeRateText: String {
        let pct = (model.feeRate * 100 as NSDecimalNumber).doubleValue
        if pct.rounded() == pct {
            return "\(Int(pct))%"
        }
        return String(format: "%.1f%%", pct)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    serviceInfoCard
                    feePreviewSection
                    paySummary
                    serverFidelityBanner
                    if showsRetryBanner {
                        retryBanner
                    }
                    agreementRow
                }
                .padding(.horizontal, 22)
                .padding(.top, 4)
                .padding(.bottom, 18)
            }
            footer
        }
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppTheme.fill, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 28, y: 14)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image("NinewoodLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text("确认预付")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppTheme.onSurface)
                Text("服务费预付用于保障服务开始，资金由平台托管")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.surfaceLow, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private var serviceInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本次服务信息")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.onSurface)

            infoRow(icon: "doc.text", label: "需求标题", value: model.demandTitle)
            infoRow(icon: "person", label: "需方", value: model.requesterName)
            infoRow(icon: "building.2", label: "服务方", value: model.providerName)
            infoRow(icon: "yensign.circle", label: "服务金额（已协商）", value: model.agreedAmount.pointsText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(red: 0.97, green: 0.98, blue: 0.99),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppTheme.fill, lineWidth: 1)
        }
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondaryLabel)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondaryLabel)
                .frame(width: 108, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var feePreviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("平台收取服务费（服务器预付预览）")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.onSurface)
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.primary)
                Spacer()
                Text("规则版本 \(model.ruleVersion)")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }

            feeRow("资金托管（服务金额）", model.escrowAmount.pointsText)
            feeRow("服务费率", feeRateText)
            feeRow("服务费金额", model.serviceFee.pointsText)
        }
    }

    private func feeRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.secondaryLabel)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.onSurface)
        }
    }

    private var paySummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(AppTheme.fill)
            HStack {
                Text("本次需支付（服务费）")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.onSurface)
                Spacer()
                Text(model.serviceFee.pointsText)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.primary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("支付后钱包余额（预估）")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryLabel)
                Spacer()
                Text("\(model.balanceAfterPay.pointsText)（当前余额：\(model.balance.pointsText)）")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.onSurface)
                    .multilineTextAlignment(.trailing)
            }
            Text("以支付成功后实际余额为准")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryLabel)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var serverFidelityBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.primary)
                .padding(.top, 1)
            Text("本预览数据由服务器根据当前规则实时计算，未使用任何客户端估算。资金将全额托管于平台，服务完成并验收通过后，服务金额再将按规则结算给服务方。")
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(red: 0.90, green: 0.96, blue: 0.99),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppTheme.primary.opacity(0.28), lineWidth: 1)
        }
    }

    private var retryBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.urgent)
            VStack(alignment: .leading, spacing: 2) {
                Text("无法获取预付预览")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppTheme.countdownForeground)
                Text("请稍后重试或联系平台客服。")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            Spacer(minLength: 8)
            Button("重新获取", action: onRetryPreview)
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(red: 1.0, green: 0.97, blue: 0.90),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(red: 0.94, green: 0.80, blue: 0.45), lineWidth: 1)
        }
    }

    private var agreementRow: some View {
        Button {
            model.agreedChecked.toggle()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: model.agreedChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(model.agreedChecked ? AppTheme.primary : Color(red: 0.70, green: 0.72, blue: 0.75))
                (
                    Text("我已阅读并同意")
                        .foregroundStyle(AppTheme.onSurface)
                    + Text("《Ninewood 服务协议》")
                        .foregroundStyle(AppTheme.primary)
                    + Text("与")
                        .foregroundStyle(AppTheme.onSurface)
                    + Text("《服务费规则》")
                        .foregroundStyle(AppTheme.primary)
                )
                .font(.system(size: 12))
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()
            Button("取消", action: onCancel)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.onSurface)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color(red: 0.86, green: 0.88, blue: 0.90), lineWidth: 1)
                        }
                )
                .buttonStyle(.plain)

            Button(action: onConfirm) {
                Text(isConfirming ? "支付中…" : "确认支付 \(compactPoints(model.serviceFee))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        (model.agreedChecked && confirmEnabled && !isLoadingPreview)
                            ? AppTheme.primary
                            : AppTheme.primary.opacity(0.45),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!model.agreedChecked || !confirmEnabled || isLoadingPreview || isConfirming)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .overlay(alignment: .top) {
            Divider().overlay(AppTheme.fill)
        }
    }

    private func compactPoints(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        let n = NSDecimalNumber(decimal: value)
        return "\(formatter.string(from: n) ?? n.stringValue) 点"
    }
}

// MARK: - Order detail backdrop (matches rendering)

private struct PaymentPrepayOrderBackdrop: View {
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            main
        }
        .background(Color(red: 0.945, green: 0.949, blue: 0.953))
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image("NinewoodLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 34)
                Text("Ninewood / 九木")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.onSurface)
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 28)

            sidebarItem("square.grid.2x2", "工作台", active: false)
            sidebarItem("doc.text", "服务订单", active: true)
            sidebarItem("bubble.left.and.bubble.right", "消息", active: false, badge: 2)
            sidebarItem("folder", "项目管理", active: false)
            sidebarItem("creditcard", "钱包", active: false)

            Spacer()

            sidebarItem("gearshape", "设置", active: false)
            sidebarItem("questionmark.circle", "帮助与支持", active: false)

            HStack(spacing: 10) {
                Text("林")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.primary, in: Circle())
                Text("林一")
                    .font(.system(size: 13, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .frame(width: 200)
        .background(Color(red: 0.965, green: 0.968, blue: 0.972))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppTheme.outlineVariant)
                .frame(width: 1)
        }
    }

    private func sidebarItem(_ icon: String, _ title: String, active: Bool, badge: Int? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .frame(width: 18)
            Text(title)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
            Spacer()
            if let badge {
                Text("\(badge)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(AppTheme.error, in: Capsule())
            }
        }
        .foregroundStyle(active ? AppTheme.primary : AppTheme.secondaryLabel)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            active ? AppTheme.primary.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("服务订单 / 订单详情")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            .padding(.top, 18)

            HStack(alignment: .top, spacing: 16) {
                leftColumn
                rightColumn
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            metaRow("订单号", value: {
                Text("SO-202607-0117")
                    .font(.system(size: 13, weight: .medium).monospaced())
            })
            metaRow("状态", value: {
                Text("进行中")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(AppTheme.primary.opacity(0.12), in: Capsule())
            })
            metaRow("创建时间", value: {
                Text("2026-07-15 10:24")
                    .font(.system(size: 13))
            })
            metaRow("需求标题", value: {
                Text("产品需求与用户反馈整理")
                    .font(.system(size: 13, weight: .medium))
            })

            VStack(alignment: .leading, spacing: 8) {
                Text("需求描述")
                    .font(.system(size: 13, weight: .semibold))
                Text("整理产品需求文档与用户反馈，形成结构化分析与优化建议。")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ninewoodCard()

            VStack(alignment: .leading, spacing: 10) {
                Text("附件（2）")
                    .font(.system(size: 13, weight: .semibold))
                attachmentRow(icon: "doc.richtext", tint: Color(red: 0.25, green: 0.45, blue: 0.85), name: "需求文档 v1.2.docx")
                attachmentRow(icon: "tablecells", tint: Color(red: 0.20, green: 0.55, blue: 0.35), name: "用户反馈汇总.xlsx")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ninewoodCard()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Text("服务方信息")
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 10) {
                    Text("思")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(AppTheme.primary, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("思远工作室")
                            .font(.system(size: 14, weight: .semibold))
                        Text("已通过平台认证")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.openStatus)
                    }
                }
                Button("联系服务方") {}
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(AppTheme.primary.opacity(0.45), lineWidth: 1)
                    )
                    .foregroundStyle(AppTheme.primary)
                    .buttonStyle(.plain)
            }
            .padding(14)
            .ninewoodCard()

            VStack(alignment: .leading, spacing: 6) {
                Text("服务金额（已协商）")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("600 点")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(AppTheme.onSurface)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ninewoodCard()

            VStack(alignment: .leading, spacing: 12) {
                Text("订单进度")
                    .font(.system(size: 13, weight: .semibold))
                progressStep("需求确认", detail: "2026-07-15 10:30", state: .done)
                progressStep("服务费预付", detail: "待确认", state: .current)
                progressStep("服务进行中", detail: "待开始", state: .todo)
                progressStep("交付与验收", detail: "待开始", state: .todo)
                progressStep("订单完成", detail: "待开始", state: .todo)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ninewoodCard()

            Spacer(minLength: 0)

            Button("查看订单留言") {}
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(red: 0.86, green: 0.88, blue: 0.90), lineWidth: 1)
                )
                .foregroundStyle(AppTheme.onSurface)
                .buttonStyle(.plain)
        }
        .frame(width: 260, alignment: .topLeading)
    }

    private enum ProgressState { case done, current, todo }

    private func progressStep(_ title: String, detail: String, state: ProgressState) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(state == .todo ? Color(red: 0.86, green: 0.88, blue: 0.90) : AppTheme.primary)
                .frame(width: 10, height: 10)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: state == .current ? .semibold : .regular))
                    .foregroundStyle(state == .todo ? AppTheme.secondaryLabel : AppTheme.onSurface)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
        }
    }

    private func metaRow<V: View>(_ label: String, @ViewBuilder value: () -> V) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondaryLabel)
                .frame(width: 64, alignment: .leading)
            value()
            Spacer(minLength: 0)
        }
    }

    private func attachmentRow(icon: String, tint: Color, name: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.onSurface)
            Spacer()
        }
        .padding(8)
        .background(Color(red: 0.97, green: 0.98, blue: 0.99), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

#Preview("26 Payment Sheet") {
    PaymentPrepayDesignPreview()
}
