import SwiftUI

@main
struct ninewood_macosApp: App {
    @State private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .environment(session.authSession)
                .environment(session.inbox)
                .tint(AppTheme.primary)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("九木") {
                Button("刷新未读") {
                    Task { await session.refreshUnread() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button("退出登录") {
                    Task { await session.logout() }
                }
                .disabled(!session.isLoggedIn)
            }
        }
    }
}
