import Foundation

/// UI 可消费的实时消息快照；与 Socket.IO 实现解耦，便于状态模型独立测试。
struct RealtimeIncomingMessage: Equatable, Identifiable {
    let id: String
    let fromUserId: String
    let toUserId: String
    let content: String
    let createdAt: Date
    let hasCardAttachment: Bool
    let mergeId: String?
}
