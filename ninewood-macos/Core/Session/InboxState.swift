import Foundation
import Observation

@Observable
@MainActor
final class InboxState {
    private(set) var unreadMessageCount = 0
    private(set) var lastError: String?

    private let messages: MessageService

    init(messages: MessageService) {
        self.messages = messages
    }

    func refresh(isAuthenticated: Bool) async {
        guard isAuthenticated else {
            reset()
            return
        }
        do {
            unreadMessageCount = try await messages.unreadCount()
            lastError = nil
        } catch APIError.rateLimited {
            // 限流时保留上次计数，避免启动连环失败
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func reset() {
        unreadMessageCount = 0
        lastError = nil
    }

    /// 打开会话时本地扣减未读（后端无 mark-read 接口时的乐观更新）
    func applyLocalRead(count: Int) {
        guard count > 0 else { return }
        unreadMessageCount = max(0, unreadMessageCount - count)
    }
}
