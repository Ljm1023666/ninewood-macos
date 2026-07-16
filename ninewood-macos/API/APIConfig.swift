import Foundation

enum APIConfig {
    /// 与 Windows / iOS 共用的 Ninewood 云端 API。
    static let productionBaseURL = URL(string: "https://tothetomorrow.com/api")!

    static var baseURL: URL {
        if let override = ProcessInfo.processInfo.environment["NINEWOOD_API_BASE"],
           let url = URL(string: override),
           url.scheme == "https" {
            return url
        }
        // 兼容 iOS 联调环境变量
        if let override = ProcessInfo.processInfo.environment["JIUMU_API_BASE"],
           let url = URL(string: override),
           url.scheme == "https" {
            return url
        }
        return productionBaseURL
    }

    static var socketBaseURL: URL {
        if let override = ProcessInfo.processInfo.environment["NINEWOOD_SOCKET_BASE"],
           let url = URL(string: override),
           url.scheme == "https" {
            return url
        }
        if let override = ProcessInfo.processInfo.environment["JIUMU_SOCKET_BASE"],
           let url = URL(string: override),
           url.scheme == "https" {
            return url
        }
        return baseURL.deletingLastPathComponent()
    }

    static let requestTimeout: TimeInterval = 15

    /// 静态资源根（`/uploads/...`），不是 `/api`。
    static var mediaBaseURL: URL { socketBaseURL }

    /// 将 API 返回的相对路径解析为可加载的 HTTPS URL。
    static func mediaURL(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        if path.hasPrefix("/") {
            return mediaBaseURL.appending(path: String(path.dropFirst()))
        }
        return mediaBaseURL.appending(path: path)
    }
}
