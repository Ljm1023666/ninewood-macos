import SwiftUI

struct LoginView: View {
    @Bindable var session: AppSession
    @State private var phone = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showRegister = false
    @State private var showForgotPassword = false

    private var canSubmit: Bool {
        phone.count >= 11 && password.count >= 1 && !isLoading
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                // 固定左栏宽度：登录/注册只换右侧，避免整页错位
                AuthBrandPanel(
                    showsCornerLabel: !showRegister,
                    logoSide: AuthDesign.authLogoSide,
                    background: showRegister
                        ? AuthDesign.registerPageBackground
                        : AuthDesign.leftBackground
                )
                .frame(width: max(proxy.size.width * AuthDesign.authBrandRatio, AuthDesign.authBrandMinWidth))

                Divider().overlay(AuthDesign.fieldBorder)

                Group {
                    if showRegister {
                        RegisterView(session: session) {
                            showRegister = false
                        }
                    } else {
                        loginForm
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.surface)
            }
        }
        .background(
            showRegister
                ? AuthDesign.registerPageBackground
                : AuthDesign.leftBackground
        )
        .alert("登录失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showForgotPassword) {
            ResetPasswordSheet(session: session, initialPhone: phone)
                .frame(minWidth: 420, minHeight: 360)
        }
    }

    private var loginForm: some View {
        AuthLoginFormLayout(
            phone: $phone,
            password: $password,
            connectionReachable: session.backendReachable,
            connectionMessage: session.backendReachable
                ? "已连接到 Ninewood 云服务"
                : (session.backendStatusMessage.isEmpty ? "服务暂不可用" : session.backendStatusMessage),
            onRetryConnection: { Task { await session.checkBackend() } },
            canSubmit: canSubmit,
            isLoading: isLoading
        ) {
            AuthPrimaryButton(
                title: "登录",
                enabled: canSubmit,
                isLoading: isLoading,
                height: 50
            ) {
                Task { await submit() }
            }
        } registerAction: {
            Button("注册") { showRegister = true }
                .buttonStyle(.plain)
                .foregroundStyle(AuthDesign.brand)
        } forgotAction: {
            Button("忘记密码？") { showForgotPassword = true }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(AuthDesign.brand)
        }
    }

    private func submit() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await session.login(phone: phone, password: password)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct ResetPasswordSheet: View {
    @Bindable var session: AppSession
    @Environment(\.dismiss) private var dismiss

    @State private var phone: String
    @State private var code = ""
    @State private var newPassword = ""
    @State private var isSendingCode = false
    @State private var isSubmitting = false
    @State private var feedback: String?
    @State private var didSucceed = false
    @State private var sentHint: String?
    @State private var captchaSiteKey: String?

    init(session: AppSession, initialPhone: String) {
        self.session = session
        _phone = State(initialValue: initialPhone)
    }

    private var canSendCode: Bool {
        phone.count >= 11 && !isSendingCode && !isSubmitting
    }

    private var canSubmit: Bool {
        phone.count >= 11 && code.count >= 4 && newPassword.count >= 6 && !isSubmitting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("重置密码")
                .font(.title2.bold())
            Text("通过手机验证码设置新密码。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("手机号", text: $phone)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                TextField("验证码", text: $code)
                    .textFieldStyle(.roundedBorder)
                Button(isSendingCode ? "发送中…" : "发送验证码") {
                    Task { await sendCode() }
                }
                .disabled(!canSendCode)
            }
            if let sentHint {
                Text(sentHint)
                    .font(.caption)
                    .foregroundStyle(AppTheme.openStatus)
            }
            SecureField("新密码（至少 6 位）", text: $newPassword)
                .textFieldStyle(.roundedBorder)

            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(didSucceed ? AppTheme.openStatus : AppTheme.error)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isSubmitting ? "提交中…" : "重置密码") {
                    Task { await submit() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .sheet(isPresented: Binding(
            get: { captchaSiteKey != nil },
            set: { if !$0 { captchaSiteKey = nil } }
        )) {
            if let captchaSiteKey {
                HCaptchaChallengeView(
                    siteKey: captchaSiteKey,
                    onSolved: { token in
                        self.captchaSiteKey = nil
                        Task { await verifyAndSendResetCode(challengeToken: token) }
                    },
                    onCancel: { self.captchaSiteKey = nil }
                )
            }
        }
    }

    private func sendCode() async {
        isSendingCode = true
        feedback = nil
        sentHint = nil
        defer { isSendingCode = false }
        do {
            let status = try await session.captchaService.status()
            let siteKey = status.siteKey ?? ""
            if status.mode == "bypass" || siteKey.isEmpty {
                try await sendResetCodeRequest(
                    captchaToken: CaptchaService.unconfiguredBypassToken
                )
            } else {
                captchaSiteKey = siteKey
            }
        } catch {
            feedback = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func verifyAndSendResetCode(challengeToken: String) async {
        isSendingCode = true
        feedback = nil
        defer { isSendingCode = false }
        do {
            let verifiedToken = try await session.captchaService.verifyChallengeToken(challengeToken)
            try await sendResetCodeRequest(captchaToken: verifiedToken)
        } catch {
            feedback = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func sendResetCodeRequest(captchaToken: String) async throws {
        let result = try await session.authService.sendResetCode(
            phone: phone,
            captchaToken: captchaToken
        )
        if let returnedCode = result.code, !returnedCode.isEmpty {
            sentHint = "验证码已发送（开发通道：\(returnedCode)）"
            code = returnedCode
        } else {
            sentHint = "验证码已发送，请查收短信"
        }
    }

    private func submit() async {
        isSubmitting = true
        feedback = nil
        didSucceed = false
        defer { isSubmitting = false }
        do {
            try await session.authService.resetPassword(
                phone: phone,
                code: code,
                newPassword: newPassword
            )
            didSucceed = true
            feedback = "密码已重置，请使用新密码登录"
            try? await Task.sleep(nanoseconds: 800_000_000)
            dismiss()
        } catch {
            feedback = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
