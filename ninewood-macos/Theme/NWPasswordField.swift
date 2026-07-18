import SwiftUI

/// 密码强度规则（对齐常见前端 PasswordInput 校验清单）。
struct NWPasswordRequirement: Identifiable, Hashable {
    let id: String
    let text: String
    let regex: String

    func isMet(by password: String) -> Bool {
        password.range(of: regex, options: .regularExpression) != nil
    }

    static let standard: [NWPasswordRequirement] = [
        .init(id: "length", text: "至少 8 个字符", regex: ".{8,}"),
        .init(id: "number", text: "至少 1 个数字", regex: "[0-9]"),
        .init(id: "lower", text: "至少 1 个小写字母", regex: "[a-z]"),
        .init(id: "upper", text: "至少 1 个大写字母", regex: "[A-Z]"),
        .init(id: "special", text: "至少 1 个特殊字符", regex: "[!-/:-@\\[-`{-~]"),
    ]
}

struct NWPasswordCheckItem: Identifiable {
    let id: String
    let text: String
    let met: Bool
}

struct NWPasswordStrength {
    let score: Int
    let requirements: [NWPasswordCheckItem]

    var clampedScore: Int { min(max(score, 0), 5) }

    var summary: String {
        switch clampedScore {
        case 0: "请输入密码"
        case 1: "密码较弱"
        case 2: "密码一般"
        case 3: "密码较强"
        case 4: "密码很强"
        default: "密码非常强"
        }
    }

    var barColor: Color {
        switch clampedScore {
        case 0: AppTheme.fill
        case 1: AppTheme.error
        case 2: AppTheme.urgent
        case 3: Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255)
        case 4: Color(red: 180 / 255, green: 120 / 255, blue: 40 / 255)
        default: AppTheme.openStatus
        }
    }

    static func evaluate(
        _ password: String,
        requirements: [NWPasswordRequirement] = .standard
    ) -> NWPasswordStrength {
        let evaluated = requirements.map {
            NWPasswordCheckItem(id: $0.id, text: $0.text, met: $0.isMet(by: password))
        }
        return NWPasswordStrength(
            score: evaluated.filter(\.met).count,
            requirements: evaluated
        )
    }

    /// 与后端 `assertPasswordStrength` 对齐：≥8 且同时含字母与数字。
    static func meetsServerPolicy(_ password: String) -> Bool {
        guard password.count >= 8 else { return false }
        let hasLetter = password.range(of: "[A-Za-z]", options: .regularExpression) != nil
        let hasDigit = password.range(of: "[0-9]", options: .regularExpression) != nil
        return hasLetter && hasDigit
    }
}

/// ChatGPT / shadcn PasswordInput 风格：可见性切换 + 强度条 + 规则清单。
struct NWPasswordField: View {
    enum Mode {
        /// 登录：不阻断提交，仅在有输入时给强度提示
        case login
        /// 创建/修改：展示完整规则；可选要求达到一定强度
        case create
    }

    @Binding var text: String
    var title: String = "密码"
    var placeholder: String = "请输入密码"
    var mode: Mode = .login
    var showsRequirements: Bool = true
    var controlHeight: CGFloat = 36

    @State private var isVisible = false
    @FocusState private var isFocused: Bool

    private var strength: NWPasswordStrength {
        NWPasswordStrength.evaluate(text)
    }

    private var showsMeter: Bool {
        mode == .create || !text.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.space8) {
            Text(title)
                .font(.subheadline.weight(.medium))

            HStack(spacing: 8) {
                Group {
                    if isVisible {
                        TextField(placeholder, text: $text)
                    } else {
                        SecureField(placeholder, text: $text)
                    }
                }
                .textFieldStyle(.plain)
                .textContentType(.password)
                .focused($isFocused)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: controlHeight, alignment: .leading)

                Button {
                    isVisible.toggle()
                } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: controlHeight)
                }
                .buttonStyle(.plain)
                .help(isVisible ? "隐藏密码" : "显示密码")
                .padding(.trailing, 4)
            }
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isFocused ? AppTheme.primary : AppTheme.outlineVariant,
                        lineWidth: isFocused ? 2 : 1
                    )
            }

            if showsMeter {
                strengthBars
                if showsRequirements {
                    requirementsBlock
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var strengthBars: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(1 ... 5, id: \.self) { index in
                    Capsule()
                        .fill(strength.clampedScore >= index ? barFill(for: index) : AppTheme.fill)
                        .frame(height: 4)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("密码强度")
            .accessibilityValue(strength.summary)

            HStack {
                Text(mode == .create ? "需满足：" : "密码提示")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(strength.summary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(strength.clampedScore == 0 ? .secondary : strength.barColor)
            }
        }
    }

    private var requirementsBlock: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading)
            ],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(strength.requirements) { item in
                HStack(spacing: 8) {
                    Image(systemName: item.met ? "checkmark.circle.fill" : "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(item.met ? AppTheme.openStatus : .secondary)
                    Text(item.text)
                        .font(.caption)
                        .foregroundStyle(item.met ? AppTheme.openStatus.opacity(0.9) : .secondary)
                    Spacer(minLength: 0)
                }
                .accessibilityLabel("\(item.text)，\(item.met ? "已满足" : "未满足")")
            }
        }
        .padding(.top, 2)
    }

    private func barFill(for index: Int) -> Color {
        // 分段用绿色梯度，接近参考组件的视觉节奏
        switch index {
        case 1: Color(red: 0.72, green: 0.93, blue: 0.76)
        case 2: Color(red: 0.52, green: 0.87, blue: 0.62)
        case 3: Color(red: 0.34, green: 0.80, blue: 0.50)
        case 4: AppTheme.openStatus
        default: Color(red: 0.05, green: 0.60, blue: 0.35)
        }
    }
}

extension Array where Element == NWPasswordRequirement {
    static var standard: [NWPasswordRequirement] { NWPasswordRequirement.standard }
}
