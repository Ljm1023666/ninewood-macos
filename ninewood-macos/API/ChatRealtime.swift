import Foundation
import Observation
@preconcurrency import SocketIO

struct RealtimeIncomingMessage: Equatable, Identifiable {
    let id: String
    let fromUserId: String
    let toUserId: String
    let content: String
    let createdAt: Date
    let hasCardAttachment: Bool
    let mergeId: String?
}

/// Socket.IO 实时通道（对齐 Windows `utils/socket.ts`）
@Observable
@MainActor
final class ChatRealtime {
    private(set) var isConnected = false
    private(set) var lastIncoming: RealtimeIncomingMessage?
    /// 递增序号，便于视图 onChange 触发刷新
    private(set) var inboxEpoch: Int = 0

    var onUnreadHint: (() -> Void)?

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var pingTimer: Timer?

    func connect(token: String?) {
        disconnect()
        guard let token, !token.isEmpty else { return }

        let url = APIConfig.socketBaseURL
        let config: SocketIOClientConfiguration = [
            .log(false),
            .compress,
            .forceWebsockets(true),
            .reconnects(true),
            .connectParams(["token": token]),
            .extraHeaders(["Authorization": "Bearer \(token)"]),
        ]

        let manager = SocketManager(socketURL: url, config: config)
        let socket = manager.defaultSocket
        self.manager = manager
        self.socket = socket

        socket.on(clientEvent: .connect) { [weak self] _, _ in
            Task { @MainActor in
                self?.isConnected = true
            }
        }
        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            Task { @MainActor in self?.isConnected = false }
        }
        socket.on(clientEvent: .error) { data, _ in
            #if DEBUG
            print("[Socket] error:", data)
            #endif
        }

        socket.on("private:message") { [weak self] data, _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleIncoming(data, event: .privateMessage)
            }
        }
        socket.on("merge:message") { [weak self] data, _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleIncoming(data, event: .mergeMessage)
            }
        }
        socket.on("notification:new") { [weak self] _, _ in
            Task { @MainActor in
                self?.onUnreadHint?()
                self?.inboxEpoch += 1
            }
        }

        // 对齐 Windows io({ auth: { token } })
        socket.connect(withPayload: ["token": token])
        startPing()
    }

    func disconnect() {
        pingTimer?.invalidate()
        pingTimer = nil
        socket?.removeAllHandlers()
        socket?.disconnect()
        socket = nil
        manager = nil
        isConnected = false
    }

    private func startPing() {
        pingTimer?.invalidate()
        // 捕获当前 socket，避免计时器的并发闭包跨隔离域捕获 MainActor self。
        let activeSocket = socket
        pingTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            activeSocket?.emit("ping")
        }
    }

    private enum IncomingEvent {
        case privateMessage
        case mergeMessage
    }

    private func handleIncoming(_ data: [Any], event: IncomingEvent) {
        guard let raw = data.first, let parsed = ChatRealtimePayload.parse(raw) else { return }
        _ = event

        lastIncoming = RealtimeIncomingMessage(
            id: parsed.id,
            fromUserId: parsed.fromUserId,
            toUserId: parsed.toUserId,
            content: parsed.content,
            createdAt: parsed.createdAt,
            hasCardAttachment: parsed.hasCardAttachment,
            mergeId: parsed.mergeId
        )
        inboxEpoch += 1
        onUnreadHint?()
    }
}
