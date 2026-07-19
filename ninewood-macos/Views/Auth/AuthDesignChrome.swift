import SwiftUI

/// Shared chrome for auth screens — layout tokens aligned to
/// `docs/ui-renderings/01-login.png` and `02-register.png`.
enum AuthDesign {
    static let brand = Color(red: 47 / 255, green: 187 / 255, blue: 224 / 255) // #2FBBE0
    static let success = Color(red: 66 / 255, green: 207 / 255, blue: 165 / 255) // #42CFA5
    static let leftBackground = AppTheme.surface
    /// `02-register` 页底：暖白，衬出右侧白卡片。
    static let registerPageBackground = AppTheme.groupedBackground
    static let fieldBorder = AppTheme.outlineVariant
    static let fieldRadius: CGFloat = 8
    static let buttonRadius: CGFloat = 8
    static let fieldHeight: CGFloat = 48
    static let loginFieldHeight: CGFloat = 52
    /// Right form column content width (login rendering).
    static let loginFormMaxWidth: CGFloat = 400
    /// Register form content width inside the white card (`02-register`).
    static let registerFormMaxWidth: CGFloat = 560
    /// 登录↔注册共用壳层比例，避免切换时左栏错位跳动。
    static let authBrandRatio: CGFloat = 0.55
    static let authBrandMinWidth: CGFloat = 400
    static let authLogoSide: CGFloat = 220

    static let passwordCriteria: [(id: String, text: String, test: (String) -> Bool)] = [
        ("length", "8-20 位字符", { (8 ... 20).contains($0.count) }),
        ("case", "包含大小写字母", {
            $0.range(of: "[a-z]", options: .regularExpression) != nil
                && $0.range(of: "[A-Z]", options: .regularExpression) != nil
        }),
        ("digit", "包含数字", { $0.range(of: "[0-9]", options: .regularExpression) != nil }),
        ("special", "包含特殊字符", {
            $0.range(of: "[!-/:-@\\[-`{-~]", options: .regularExpression) != nil
        }),
    ]

    static func passwordScore(_ password: String) -> Int {
        passwordCriteria.filter { $0.test(password) }.count
    }
}

// MARK: - Brand panel (01 left)

struct AuthBrandPanel: View {
    var showsCornerLabel: Bool = true
    var logoSide: CGFloat = 220
    var background: Color = AuthDesign.leftBackground

    var body: some View {
        ZStack {
            background

            // 渲染图左下：品牌标识线稿的淡影，不是手绘乱叠菱形
            AuthBrandWatermark()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .allowsHitTesting(false)

            if showsCornerLabel {
                VStack {
                    HStack {
                        Text("Ninewood / 九木")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 36)
                .padding(.top, 28)
            }

            VStack(spacing: 12) {
                Image("NinewoodLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: logoSide, height: logoSide * 1.12)
                    .accessibilityLabel("九木标识")

                Text("九木")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(AppTheme.onSurface)

                Text("Ninewood")
                    .font(.system(size: 22, weight: .regular))
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.onSurface)

                Text("让每一个需求，都找到可靠的回应")
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .padding(.top, 4)
            }
            .offset(y: showsCornerLabel ? -12 : -6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 左下角水印：放大裁切的品牌 Logo 线稿淡影（对齐 `01-login` 渲染图，非手绘菱形）。
private struct AuthBrandWatermark: View {
    var body: some View {
        GeometryReader { proxy in
            // 比主 Logo 更大，并从左/下边缘裁出，形成渲染图那种「半截线稿」
            let side = max(proxy.size.width * 0.78, 420)
            Image("NinewoodLogo")
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side * 4 / 3)
                // 渲染图为极淡灰影；保留原色线稿再压低透明度，避免 template 把 SVG 压糊
                .opacity(0.10)
                .position(
                    x: side * 0.22,
                    y: proxy.size.height - side * 0.18
                )
        }
        .clipped()
    }
}

// MARK: - Fields

struct AuthFieldLabel: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(AppTheme.onSurface)
    }
}

struct AuthOutlinedField<Content: View>: View {
    var height: CGFloat = AuthDesign.fieldHeight
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            content()
        }
        .padding(.horizontal, 14)
        .frame(height: height)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AuthDesign.fieldRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AuthDesign.fieldRadius, style: .continuous)
                .strokeBorder(AuthDesign.fieldBorder, lineWidth: 1)
        }
    }
}

struct AuthPasswordField: View {
    @Binding var text: String
    var placeholder: String
    var leadingIcon: String? = nil
    var height: CGFloat = AuthDesign.fieldHeight
    @State private var isVisible = false

    var body: some View {
        AuthOutlinedField(height: height) {
            if let leadingIcon {
                Image(systemName: leadingIcon)
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .frame(width: 20)
            }
            Group {
                if isVisible {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            Button {
                isVisible.toggle()
            } label: {
                Image(systemName: isVisible ? "eye.slash" : "eye")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            .buttonStyle(.plain)
            .help(isVisible ? "隐藏密码" : "显示密码")
        }
    }
}

struct AuthPasswordStrengthBlock: View {
    let password: String

    private var score: Int { AuthDesign.passwordScore(password) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0 ..< 4, id: \.self) { index in
                    Capsule()
                        .fill(index < score ? AuthDesign.success : AppTheme.outlineVariant)
                        .frame(height: 4)
                        .frame(maxWidth: .infinity)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    ForEach(AuthDesign.passwordCriteria, id: \.id) { item in
                        criteriaChip(item)
                    }
                }
                LazyVGrid(
                    columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                    alignment: .leading,
                    spacing: 6
                ) {
                    ForEach(AuthDesign.passwordCriteria, id: \.id) { item in
                        criteriaChip(item)
                    }
                }
            }
        }
    }

    private func criteriaChip(_ item: (id: String, text: String, test: (String) -> Bool)) -> some View {
        let met = item.test(password)
        return HStack(spacing: 5) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11))
                .foregroundStyle(met ? AuthDesign.success : Color(red: 0.72, green: 0.74, blue: 0.76))
            Text(item.text)
                .font(.system(size: 11))
                .foregroundStyle(met ? AuthDesign.success.opacity(0.95) : AppTheme.secondaryLabel)
                .lineLimit(1)
        }
    }
}

// MARK: - Buttons & chrome

struct AuthPrimaryButton: View {
    let title: String
    var enabled: Bool
    var isLoading: Bool = false
    var height: CGFloat = 48
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(enabled ? Color.white : AppTheme.secondaryLabel)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                enabled ? AuthDesign.brand : AppTheme.fill,
                in: RoundedRectangle(cornerRadius: AuthDesign.buttonRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled || isLoading)
    }
}

struct AuthOrDivider: View {
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(AuthDesign.fieldBorder).frame(height: 1)
            Text("或")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondaryLabel)
            Rectangle().fill(AuthDesign.fieldBorder).frame(height: 1)
        }
    }
}

struct AuthSecurityBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 22))
                .foregroundStyle(AuthDesign.success)
            VStack(alignment: .leading, spacing: 4) {
                Text("多重保障，安心使用")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.onSurface)
                Text("数据加密传输，权限精细控制，7×24 小时安全守护")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppTheme.surfaceLow,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }
}

struct AuthLegalLine: View {
    var prefix: String = "登录即表示您同意"
    @State private var legalKind: LegalDocView.Kind?

    var body: some View {
        HStack(spacing: 0) {
            Text(prefix)
                .foregroundStyle(AppTheme.secondaryLabel)
            Button("《用户协议》") { legalKind = .terms }
                .buttonStyle(.plain)
                .foregroundStyle(AuthDesign.brand)
            Text("和")
                .foregroundStyle(AppTheme.secondaryLabel)
            Button("《隐私政策》") { legalKind = .privacy }
                .buttonStyle(.plain)
                .foregroundStyle(AuthDesign.brand)
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, alignment: .center)
        .multilineTextAlignment(.center)
        .sheet(item: $legalKind) { kind in
            NavigationStack {
                LegalDocView(kind: kind)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { legalKind = nil }
                        }
                    }
            }
            .frame(minWidth: 480, minHeight: 420)
        }
    }
}

struct AuthRegisterFooter: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AuthDesign.success)
                Text("云端服务正常 · 数据多重备份，服务稳定可靠")
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(AuthDesign.brand)
                Text("我们承诺严格保护你的隐私与数据安全")
                    .foregroundStyle(AppTheme.secondaryLabel)
            }
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

struct AuthConnectionStatus: View {
    var reachable: Bool = true
    var message: String = "已连接到 Ninewood 云服务"
    var onRetry: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(reachable ? AuthDesign.success : Color.red.opacity(0.75))
                .frame(width: 8, height: 8)
            Image(systemName: reachable ? "cloud" : "cloud.slash")
                .font(.system(size: 13))
                .foregroundStyle(reachable ? AuthDesign.success : Color.red.opacity(0.75))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.secondaryLabel)
            Spacer(minLength: 0)
            if !reachable, let onRetry {
                Button("重试", action: onRetry)
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(AuthDesign.brand)
            }
        }
    }
}

// MARK: - Login form shell (01) — shared by live + design preview

struct AuthLoginFormLayout<PrimaryAction: View, RegisterAction: View, ForgotAction: View>: View {
    @Binding var phone: String
    @Binding var password: String
    var connectionReachable: Bool = true
    var connectionMessage: String = "已连接到 Ninewood 云服务"
    var onRetryConnection: (() -> Void)? = nil
    var canSubmit: Bool
    var isLoading: Bool = false
    @ViewBuilder var primaryAction: () -> PrimaryAction
    @ViewBuilder var registerAction: () -> RegisterAction
    @ViewBuilder var forgotAction: () -> ForgotAction

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 48)

            Text("登录")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(AppTheme.onSurface)

            AuthConnectionStatus(
                reachable: connectionReachable,
                message: connectionMessage,
                onRetry: onRetryConnection
            )
            .padding(.top, 14)

            VStack(alignment: .leading, spacing: 8) {
                AuthFieldLabel(title: "手机号")
                AuthOutlinedField(height: AuthDesign.loginFieldHeight) {
                    Image(systemName: "iphone")
                        .font(.system(size: 16))
                        .foregroundStyle(AppTheme.secondaryLabel)
                        .frame(width: 22)
                    TextField("请输入手机号", text: $phone)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .textContentType(.telephoneNumber)
                }
            }
            .padding(.top, 28)

            VStack(alignment: .leading, spacing: 8) {
                AuthFieldLabel(title: "密码")
                AuthPasswordField(
                    text: $password,
                    placeholder: "请输入密码",
                    leadingIcon: "lock",
                    height: AuthDesign.loginFieldHeight
                )
            }
            .padding(.top, 18)

            forgotAction()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 10)

            primaryAction()
                .padding(.top, 22)

            AuthOrDivider()
                .padding(.top, 22)

            HStack(spacing: 4) {
                Spacer(minLength: 0)
                Text("没有账号？")
                    .foregroundStyle(AppTheme.secondaryLabel)
                registerAction()
                Spacer(minLength: 0)
            }
            .font(.system(size: 13))
            .padding(.top, 16)

            AuthSecurityBanner()
                .padding(.top, 28)

            Spacer(minLength: 28)

            AuthLegalLine()
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 36)
        .frame(maxWidth: AuthDesign.loginFormMaxWidth + 96)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Register form shell (02) — shared by live + design preview

struct AuthRegisterFormLayout<
    BackAction: View,
    CodeTrailing: View,
    PrimaryAction: View,
    ExtraBelowCode: View,
    ExtraBelowConfirm: View
>: View {
    @Binding var phone: String
    @Binding var code: String
    @Binding var password: String
    @Binding var confirmPassword: String
    @Binding var acceptedTerms: Bool
    @State private var legalKind: LegalDocView.Kind?
    @ViewBuilder var backAction: () -> BackAction
    @ViewBuilder var codeTrailing: () -> CodeTrailing
    @ViewBuilder var primaryAction: () -> PrimaryAction
    @ViewBuilder var extraBelowCode: () -> ExtraBelowCode
    @ViewBuilder var extraBelowConfirm: () -> ExtraBelowConfirm

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    backAction()
                }

                Text("创建九木账号")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(AppTheme.onSurface)
                    .padding(.top, 10)

                Text("欢迎加入九木，开启高效协作之旅")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.secondaryLabel)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 8) {
                    AuthFieldLabel(title: "手机号")
                    AuthOutlinedField {
                        HStack(spacing: 6) {
                            Text("+86")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppTheme.onSurface)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(AppTheme.secondaryLabel)
                        }
                        Rectangle()
                            .fill(AuthDesign.fieldBorder)
                            .frame(width: 1, height: 22)
                            .padding(.horizontal, 4)
                        TextField("请输入手机号", text: $phone)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .textContentType(.telephoneNumber)
                    }
                }
                .padding(.top, 22)

                VStack(alignment: .leading, spacing: 8) {
                    AuthFieldLabel(title: "短信验证码")
                    AuthOutlinedField {
                        TextField("请输入短信验证码", text: $code)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .textContentType(.oneTimeCode)
                        codeTrailing()
                    }
                }
                .padding(.top, 14)

                extraBelowCode()

                VStack(alignment: .leading, spacing: 8) {
                    AuthFieldLabel(title: "密码")
                    AuthPasswordField(
                        text: $password,
                        placeholder: "请设置登录密码"
                    )
                    AuthPasswordStrengthBlock(password: password)
                        .padding(.top, 4)
                }
                .padding(.top, 14)

                VStack(alignment: .leading, spacing: 8) {
                    AuthFieldLabel(title: "确认密码")
                    AuthPasswordField(
                        text: $confirmPassword,
                        placeholder: "请再次输入密码"
                    )
                }
                .padding(.top, 14)

                extraBelowConfirm()

                Toggle(isOn: $acceptedTerms) {
                    HStack(spacing: 0) {
                        Text("我已阅读并同意")
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Button("《用户协议》") { legalKind = .terms }
                            .buttonStyle(.plain)
                            .foregroundStyle(AuthDesign.brand)
                        Text("和")
                            .foregroundStyle(AppTheme.secondaryLabel)
                        Button("《隐私政策》") { legalKind = .privacy }
                            .buttonStyle(.plain)
                            .foregroundStyle(AuthDesign.brand)
                    }
                    .font(.system(size: 12))
                }
                .toggleStyle(.checkbox)
                .padding(.top, 18)
                .sheet(item: $legalKind) { kind in
                    NavigationStack {
                        LegalDocView(kind: kind)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("关闭") { legalKind = nil }
                                }
                            }
                    }
                    .frame(minWidth: 480, minHeight: 420)
                }

                primaryAction()
                    .padding(.top, 16)

                AuthRegisterFooter()
                    .padding(.top, 22)
            }
            .padding(.horizontal, 36)
            .padding(.top, 28)
            .padding(.bottom, 32)
            .frame(maxWidth: AuthDesign.registerFormMaxWidth)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
