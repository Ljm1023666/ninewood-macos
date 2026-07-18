import Foundation

/// 群聊消息在服务端会按成员 fan-out 为多行；展示时间线时需去重。
enum MessageMergeDeduper {
    /// 保留与当前用户相关的时间线消息，并对发送者自己的 fan-out 副本去重。
    static func timeline(_ messages: [MessageDTO], viewerID: String) -> [MessageDTO] {
        guard !messages.isEmpty else { return [] }

        var seenOwnBuckets: Set<String> = []
        var result: [MessageDTO] = []

        for message in messages {
            if message.fromUserId == viewerID {
                let bucket = ownSendBucket(message)
                guard !seenOwnBuckets.contains(bucket) else { continue }
                seenOwnBuckets.insert(bucket)
                result.append(message)
                continue
            }

            if message.toUserId == viewerID {
                result.append(message)
            }
        }

        return result
    }

    private static func ownSendBucket(_ message: MessageDTO) -> String {
        let secondBucket = message.createdAt?
            .prefix(19)
            .description ?? message.id
        return "\(message.fromUserId)|\(message.content)|\(secondBucket)"
    }
}
