import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?, requestID: String?)
    case server(statusCode: Int, errorCode: String?, message: String, requestID: String?)
    case decoding(Error, requestID: String?)
    case transport(Error)

    var requestID: String? {
        switch self {
        case let .rateLimited(_, requestID), let .server(_, _, _, requestID), let .decoding(_, requestID):
            requestID
        default:
            nil
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "请求地址无效"
        case .invalidResponse:
            "服务器响应异常"
        case .unauthorized:
            "登录已过期，请重新登录"
        case let .rateLimited(retryAfter, _):
            if let retryAfter, retryAfter > 0 {
                "操作过于频繁，请在 \(Int(retryAfter.rounded(.up))) 秒后重试"
            } else {
                "操作过于频繁，请稍后重试"
            }
        case let .server(_, _, message, requestID):
            Self.withRequestID(message, requestID: requestID)
        case let .decoding(_, requestID):
            Self.withRequestID("云端返回的数据与当前客户端版本不兼容，请更新或稍后重试", requestID: requestID)
        case let .transport(error):
            Self.transportMessage(error)
        }
    }

    private static func withRequestID(_ message: String, requestID: String?) -> String {
        guard let requestID, !requestID.isEmpty else { return message }
        return "\(message)（请求编号：\(requestID)）"
    }

    private static func transportMessage(_ error: Error) -> String {
        guard let urlError = error as? URLError else {
            return "无法连接九木云端，请稍后重试"
        }
        switch urlError.code {
        case .notConnectedToInternet:
            return "当前设备没有网络连接"
        case .networkConnectionLost:
            return "云端连接在响应前中断，请稍后重试"
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return "九木云端暂时无法访问"
        case .timedOut:
            return "连接九木云端超时，请稍后重试"
        case .secureConnectionFailed, .serverCertificateUntrusted,
             .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot:
            return "九木云端的安全连接暂时不可用"
        default:
            return "无法连接九木云端，请稍后重试"
        }
    }
}
