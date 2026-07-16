import AppKit
import Combine
import SwiftUI

/// 统一图片管线：内存缓存避免页面切换重载，磁盘缓存避免重启后重新下载。
private enum NWImagePipeline {
    static let memory = NSCache<NSURL, NSImage>()

    static let disk: URLCache = {
        URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024,
            diskPath: "ninewood-remote-images"
        )
    }()

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = disk
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    static func cachedImage(for url: URL) -> NSImage? {
        let key = url as NSURL
        if let image = memory.object(forKey: key) {
            return image
        }

        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        guard let response = disk.cachedResponse(for: request),
              let image = NSImage(data: response.data) else {
            return nil
        }
        memory.setObject(image, forKey: key)
        return image
    }

    static func load(_ url: URL) async throws -> NSImage {
        if let image = cachedImage(for: url) {
            return image
        }

        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse,
           !(200 ... 299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard let image = NSImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }

        memory.setObject(image, forKey: url as NSURL)
        disk.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
        return image
    }

    /// 用像素尺寸算比例，避免 NSImage.point size 失真。
    static func pixelAspectRatio(of image: NSImage) -> CGFloat {
        if let rep = image.representations.first(where: { $0.pixelsWide > 0 && $0.pixelsHigh > 0 }) {
            return CGFloat(rep.pixelsWide) / CGFloat(rep.pixelsHigh)
        }
        guard image.size.height > 0 else { return 1 }
        return image.size.width / image.size.height
    }
}

enum NWImageFit {
    /// 铺满并裁切（仅头像等固定几何）
    case fill
    /// 完整显示，不裁主体（列表/封面）
    case fit
}

@MainActor
private final class NWImageLoader: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var isLoading = false
    private var loadedURL: URL?

    var aspectRatio: CGFloat {
        guard let image else { return 1 }
        return NWImagePipeline.pixelAspectRatio(of: image)
    }

    func load(_ url: URL?) async {
        guard loadedURL != url else { return }
        loadedURL = url
        image = nil
        guard let url else {
            isLoading = false
            return
        }

        if let cached = NWImagePipeline.cachedImage(for: url) {
            withAnimation(.easeOut(duration: 0.2)) { image = cached }
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await NWImagePipeline.load(url)
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        } catch is CancellationError {
        } catch {
            image = nil
        }
    }
}

/// 在父级给定的框内绘制：fill 会裁，fit 完整可见。
private struct NWRasterImage: View {
    let image: NSImage
    var fit: NWImageFit

    var body: some View {
        switch fit {
        case .fill:
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
        case .fit:
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct NWCachedRemoteImage<Placeholder: View>: View {
    let url: URL?
    var fit: NWImageFit = .fill
    @ViewBuilder let placeholder: () -> Placeholder
    @StateObject private var loader = NWImageLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                NWRasterImage(image: image, fit: fit)
                    .transition(.opacity)
            } else {
                placeholder()
                    .overlay {
                        if loader.isLoading {
                            ProgressView().controlSize(.small)
                        }
                    }
            }
        }
        .task(id: url) {
            await loader.load(url)
        }
    }
}

/// 圆形头像：固定圆内 fill 裁切。
struct NWAvatarView: View {
    var url: URL?
    var name: String
    var size: CGFloat = 40

    var body: some View {
        NWCachedRemoteImage(url: url, fit: .fill) {
            placeholder
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(AppTheme.outlineVariant.opacity(0.5), lineWidth: 0.5)
        }
    }

    private var placeholder: some View {
        Circle()
            .fill(AppTheme.fill.opacity(0.7))
            .overlay {
                Text(String(name.prefix(1)))
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
            }
    }
}

/// 通用圆角图。调用方必须给明确 frame；默认 fit，不硬裁。
struct NWRemoteImage: View {
    var url: URL?
    var cornerRadius: CGFloat = 10
    var systemFallback: String = "photo"
    var fit: NWImageFit = .fit

    var body: some View {
        NWCachedRemoteImage(url: url, fit: fit) {
            fallback
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(AppTheme.fill.opacity(0.55))
            .overlay {
                Image(systemName: systemFallback)
                    .foregroundStyle(.secondary)
            }
    }
}

/// 列表缩略图：外框固定；`portrait` 给卡池/需求立绘，`landscape` 给横版封面。
struct NWListThumbnail: View {
    enum Aspect {
        /// 约 3:4，适合立绘 / 卡池
        case portrait
        /// 约 3:2，适合横版封面
        case landscape

        var size: (width: CGFloat, height: CGFloat) {
            switch self {
            case .portrait: (56, 74)
            case .landscape: (72, 48)
            }
        }
    }

    var url: URL?
    var title: String
    var aspect: Aspect = .landscape
    var cornerRadius: CGFloat = 8

    private var width: CGFloat { aspect.size.width }
    private var height: CGFloat { aspect.size.height }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppTheme.fill.opacity(0.5))

            if url != nil {
                NWCachedRemoteImage(url: url, fit: .fill) {
                    Color.clear
                }
            } else {
                Text(monogram)
                    .font(.system(size: min(width, height) * 0.36, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant.opacity(0.7), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    private var monogram: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "·" }
        return String(first)
    }
}

/// 详情主图：铺满限定框并裁切多余部分，不留白边。
struct NWHeroImage: View {
    var url: URL?
    var maxHeight: CGFloat = 360
    var cornerRadius: CGFloat = 12
    var systemFallback: String = "doc.text.image"

    var body: some View {
        NWCachedRemoteImage(url: url, fit: .fill) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppTheme.fill.opacity(0.4))
                .overlay {
                    Image(systemName: systemFallback)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
        }
        .frame(maxWidth: .infinity)
        .frame(height: maxHeight)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(AppTheme.outlineVariant, lineWidth: 1)
        }
    }
}

/// 个人主页横幅：固定高度，铺满裁切。
struct NWProfileBanner: View {
    var coverURL: URL?
    var height: CGFloat = 140

    var body: some View {
        NWCachedRemoteImage(url: coverURL, fit: .fill) {
            LinearGradient(
                colors: [AppTheme.primary.opacity(0.18), AppTheme.fill],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}
