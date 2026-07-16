import SwiftUI

struct ContentView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Group {
            switch session.state {
            case .bootstrapping:
                launchView
            case .signedOut:
                LoginView(session: session)
            case .signedIn:
                MainShellView()
            case let .serviceUnavailable(message):
                serviceUnavailableView(message: message)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.state)
        .task {
            await session.bootstrap()
        }
    }

    private var launchView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("正在连接九木云端…")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryLabel)
            Text("若长时间无响应，多半是请求过于频繁，请稍后再试")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.groupedBackground)
    }

    private func serviceUnavailableView(message: String) -> some View {
        ContentUnavailableView {
            Label("云端暂不可用", systemImage: "cloud.slash")
        } description: {
            Text("\(message)\n\n你的登录凭据仍安全保留。恢复连接后，九木会重新向云端确认账号和业务状态。")
        } actions: {
            Button("重新连接") {
                Task { await session.retryBootstrap() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(AppTheme.groupedBackground)
    }
}

#Preview {
    ContentView()
        .environment(AppSession())
}
