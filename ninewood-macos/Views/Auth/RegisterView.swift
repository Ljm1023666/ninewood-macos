import SwiftUI

/// 注册表单（右侧栏）。外层壳由 `LoginView` 统一提供，避免登录↔注册切换时左栏错位。
struct RegisterView: View {
    @Bindable var session: AppSession
    var onBackToLogin: () -> Void

    @State private var phone = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var code = ""
    /// 渲染图无出生日期栏；提交仍带成年默认值以满足 API 契约。
    @State private var birthday = Calendar.current.date(
        byAdding: .year,
        value: -20,
        to: Date()
    ) ?? Date()
    @State private var acceptedTerms = false
    @State private var isSendingCode = false
    @State private var isSubmitting = false
    @State private var countdown = 0
    @State private var fallbackCodeHint: String?
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    private let birthdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var canSendCode: Bool {
        phone.count == 11 && !isSendingCode && countdown == 0 && !isSubmitting
    }

    private var canSubmit: Bool {
        phone.count == 11
            && code.count == 6
            && AuthDesign.passwordScore(password) >= 3
            && confirmPassword == password
            && acceptedTerms
            && !isSubmitting
    }

    var body: some View {
        AuthRegisterFormLayout(
            phone: $phone,
            code: $code,
            password: $password,
            confirmPassword: $confirmPassword,
            acceptedTerms: $acceptedTerms,
            backAction: {
                Button("← 返回登录") { onBackToLogin() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(AuthDesign.brand)
            },
            codeTrailing: {
                Button {
                    Task { await sendCode() }
                } label: {
                    if isSendingCode {
                        ProgressView().controlSize(.mini)
                    } else if countdown > 0 {
                        Text("\(countdown)s")
                            .foregroundStyle(AppTheme.secondaryLabel)
                    } else {
                        Text("获取验证码")
                            .foregroundStyle(
                                canSendCode
                                    ? AuthDesign.brand
                                    : Color(red: 0.70, green: 0.72, blue: 0.74)
                            )
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .disabled(!canSendCode)
            },
            primaryAction: {
                AuthPrimaryButton(
                    title: "注册并登录",
                    enabled: canSubmit,
                    isLoading: isSubmitting,
                    height: 48
                ) {
                    Task { await submit() }
                }
            },
            extraBelowCode: {
                Group {
                    if let fallbackCodeHint {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("当前为开发通道，验证码由服务端回传（非正式短信）")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.urgent)
                            Text("验证码：\(fallbackCodeHint)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(AppTheme.urgent)
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.urgent.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(.top, 10)
                    }
                    if let infoMessage {
                        Text(infoMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                }
            },
            extraBelowConfirm: {
                Group {
                    if !confirmPassword.isEmpty, confirmPassword != password {
                        Text("两次输入的密码不一致")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.error)
                            .padding(.top, 6)
                    }
                }
            }
        )
        .alert("注册失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task(id: countdown) {
            guard countdown > 0 else { return }
            try? await Task.sleep(for: .seconds(1))
            if countdown > 0 { countdown -= 1 }
        }
    }

    private func sendCode() async {
        isSendingCode = true
        defer { isSendingCode = false }
        infoMessage = nil
        fallbackCodeHint = nil
        do {
            let result = try await session.sendRegistrationCode(phone: phone)
            countdown = 60
            let isFallback = result.delivery == "fallback"
                || (result.code?.isEmpty == false)
            if isFallback, let returned = result.code, !returned.isEmpty {
                code = returned
                fallbackCodeHint = returned
                infoMessage = "开发通道已启用，验证码已自动填入"
            } else {
                fallbackCodeHint = nil
                infoMessage = "验证码已发送，请查收短信"
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await session.register(
                phone: phone,
                code: code,
                password: password,
                birthday: birthdayFormatter.string(from: birthday),
                guardianConsent: nil
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
