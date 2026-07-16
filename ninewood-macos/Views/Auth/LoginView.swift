import SwiftUI

struct LoginView: View {
    @Bindable var session: AppSession
    @State private var phone = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        phone.count >= 11 && password.count >= 1 && !isLoading
    }

    var body: some View {
        HStack(spacing: 0) {
            brandingPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            formPanel
                .frame(width: 400)
                .frame(maxHeight: .infinity)
                .background(AppTheme.surface)
        }
        .background(AppTheme.groupedBackground)
        .alert("登录失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var brandingPanel: some View {
        VStack(alignment: .leading, spacing: AppTheme.space16) {
            Spacer()
            Text("N")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text("九木")
                .font(.system(size: 40, weight: .bold))
            Text("Ninewood")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("让每一个需求，都找到可靠的回应")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320, alignment: .leading)
            Spacer()
            Text("与 Windows 桌面共用同一云端后端")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(AppTheme.space24 * 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(AppTheme.documentBackground)
    }

    private var formPanel: some View {
        VStack(alignment: .leading, spacing: AppTheme.space16) {
            Spacer()
            Text("登录")
                .font(.largeTitle.bold())

            backendStatusBanner

            VStack(alignment: .leading, spacing: AppTheme.space8) {
                Text("手机号")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("请输入手机号", text: $phone)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.telephoneNumber)
            }

            VStack(alignment: .leading, spacing: AppTheme.space8) {
                Text("密码")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Group {
                        if showPassword {
                            TextField("请输入密码", text: $password)
                        } else {
                            SecureField("请输入密码", text: $password)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(showPassword ? "隐藏密码" : "显示密码")
                }
            }

            Button {
                Task { await submit() }
            } label: {
                Group {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("登录")
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 36)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)

            Text("与 Ninewood Web / Windows 共用账号 · 平台担保交易")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            Text("登录即表示你已阅读并同意《用户协议》和《隐私政策》")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
    }

    private var backendStatusBanner: some View {
        VStack(alignment: .leading, spacing: AppTheme.space8) {
            HStack(spacing: AppTheme.space8) {
                Circle()
                    .fill(session.backendReachable ? AppTheme.openStatus : AppTheme.error)
                    .frame(width: 8, height: 8)
                Text(session.backendStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !session.backendReachable {
                    Button("重试") {
                        Task { await session.checkBackend() }
                    }
                    .font(.caption)
                }
            }
            if !session.backendReachable {
                Text("云端地址：\(APIConfig.baseURL.absoluteString)。若使用 Clash/VPN，可尝试关闭增强模式后重试。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(AppTheme.fill.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
