import Foundation
import Observation
import SocketIO

struct RealtimeIncomingMessage: Equatable, Identifiable {
    let id: String
    let fromUserId: String
    let toUserId: String
    let content: String
    let createdAt: Date
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
                self.handlePrivateMessage(data)
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
        pingTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.socket?.emit("ping")
            }
        }
    }

    private func handlePrivateMessage(_ data: [Any]) {
        guard let raw = data.first else { return }
        let dict: [String: Any]
        if let d = raw as? [String: Any] {
            dict = d
        } else if let d = raw as? NSDictionary {
            dict = d as? [String: Any] ?? [:]
        } else {
            return
        }

        let from = (dict["fromUserId"] as? String)
            ?? (dict["senderId"] as? String)
            ?? ((dict["fromUser"] as? [String: Any])?["id"] as? String)
            ?? ""
        let to = (dict["toUserId"] as? String)
            ?? (dict["receiverId"] as? String)
            ?? ""
        let content = (dict["content"] as? String) ?? ""
        guard !from.isEmpty, !content.isEmpty else { return }

        let id = (dict["id"] as? String) ?? UUID().uuidString
        let createdAt: Date
        if let iso = dict["createdAt"] as? String, let d = APIDate.parse(iso) {
            createdAt = d
        } else {
            createdAt = Date()
        }

        lastIncoming = RealtimeIncomingMessage(
            id: id,
            fromUserId: from,
            toUserId: to,
            content: content,
            createdAt: createdAt
        )
        inboxEpoch += 1
        onUnreadHint?()
    }
}
