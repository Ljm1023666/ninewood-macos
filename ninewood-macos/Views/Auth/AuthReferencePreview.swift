import SwiftUI

/// Frontend-only reproductions of `01-login` / `02-register` renderings.
/// Local state only — no AppSession / network — for `NINEWOOD_DESIGN_PREVIEW`.
struct AuthReferencePreview: View {
    enum Mode { case login, register }
    let mode: Mode

    /// Seeded so the primary button matches the rendering’s active blue state.
    /// 统一测试账号：19900001234 / Test1234
    @State private var phone = "19900001234"
    @State private var password = "Test1234"
    @State private var confirmPassword = "Test1234"
    @State private var code = "123456"
    @State private var agreed = true
    @State private var showRegister = false

    private var isRegister: Bool {
        mode == .register || showRegister
    }

    var body: some View {
        // 与真机一致：同一壳层，只换右侧，避免预览里切换也错位
        GeometryReader { proxy in
            HStack(spacing: 0) {
                AuthBrandPanel(
                    showsCornerLabel: !isRegister,
                    logoSide: AuthDesign.authLogoSide,
                    background: isRegister
                        ? AuthDesign.registerPageBackground
                        : AuthDesign.leftBackground
                )
                .frame(width: max(proxy.size.width * AuthDesign.authBrandRatio, AuthDesign.authBrandMinWidth))

                Divider().overlay(AuthDesign.fieldBorder)

                Group {
                    if isRegister {
                        registerForm
                    } else {
                        loginForm
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.surface)
            }
        }
        .background(
            isRegister
                ? AuthDesign.registerPageBackground
                : AuthDesign.leftBackground
        )
        .onAppear {
            showRegister = (mode == .register)
        }
    }

    private var loginForm: some View {
        AuthLoginFormLayout(
            phone: $phone,
            password: $password,
            connectionReachable: true,
            connectionMessage: "已连接到 Ninewood 云服务",
            canSubmit: phone.count >= 11 && !password.isEmpty
        ) {
            AuthPrimaryButton(
                title: "登录",
                enabled: phone.count >= 11 && !password.isEmpty,
                height: 50
            ) {}
        } registerAction: {
            Button("注册") { showRegister = true }
                .buttonStyle(.plain)
                .foregroundStyle(AuthDesign.brand)
        } forgotAction: {
            Button("忘记密码？") {}
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(AuthDesign.brand)
        }
    }

    private var registerForm: some View {
        AuthRegisterFormLayout(
            phone: $phone,
            code: $code,
            password: $password,
            confirmPassword: $confirmPassword,
            acceptedTerms: $agreed,
            backAction: {
                Button("← 返回登录") {
                    if mode == .login {
                        showRegister = false
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(AuthDesign.brand)
            },
            codeTrailing: {
                Button("获取验证码") {}
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AuthDesign.brand)
            },
            primaryAction: {
                AuthPrimaryButton(
                    title: "注册并登录",
                    enabled: phone.count >= 11
                        && code.count >= 4
                        && AuthDesign.passwordScore(password) >= 3
                        && confirmPassword == password
                        && agreed,
                    height: 48
                ) {}
            },
            extraBelowCode: { EmptyView() },
            extraBelowConfirm: { EmptyView() }
        )
    }
}
