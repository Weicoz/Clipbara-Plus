import AppKit
import Foundation

struct ThumbnailImageCache {
    private nonisolated(unsafe) static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    static func image(for item: ClipboardItem) -> NSImage? {
        let cacheKey = item.id.uuidString as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let data = item.thumbnailData ?? item.rawData
        guard let bitmap = ImageThumbnail.image(from: data) else { return nil }
        let image = NSImage(cgImage: bitmap, size: .zero)
        // Compressed file size understates the decoded bitmap's memory cost.
        cache.setObject(image, forKey: cacheKey, cost: bitmap.bytesPerRow * bitmap.height)
        return image
    }
}
