import SwiftUI

/// 承接人回占位：完整 PathSearch 下轮迁入。
struct LoopAcceptPlaceholderView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 40)
            Image(systemName: "person.2")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.primary)
            Text("承接人回")
                .font(.title.bold())
            Text("服务者在这里用路径检索寻找可接的人回。完整路径检索工作台将在下一轮迁入；当前可先去发现回或查看我的回。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            HStack(spacing: 12) {
                Button("去发现回") {
                    _ = session.navigation.navigate(to: "/loops/discover")
                }
                .buttonStyle(.borderedProminent)

                Button("看我的回") {
                    _ = session.navigation.navigate(to: "/loops/mine")
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("loop-accept-placeholder")
    }
}
