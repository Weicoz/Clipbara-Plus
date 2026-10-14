import AppKit
import Foundation

@MainActor
struct ThumbnailImageCache {
    private static let cache = NSCache<NSString, NSImage>()
    private static var cachedMode: Bool?

    static func image(for item: ClipboardItem) -> NSImage? {
        let lowMemory = PlusSettings.lowMemoryImages
        if cachedMode != lowMemory {
            cache.removeAllObjects()
            cache.countLimit = lowMemory ? 64 : 180
            cache.totalCostLimit = (lowMemory ? 8 : 48) * 1024 * 1024
            cachedMode = lowMemory
        }
        let cacheKey = item.id.uuidString as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let data = item.thumbnailData ?? item.rawData
        if !lowMemory {
            guard let image = NSImage(data: data) else { return nil }
            cache.setObject(image, forKey: cacheKey, cost: data.count)
            return image
        }
        guard let bitmap = ImageThumbnail.image(from: data) else { return nil }
        let image = NSImage(cgImage: bitmap, size: .zero)
        // Compressed file size understates the decoded bitmap's memory cost.
        cache.setObject(image, forKey: cacheKey, cost: bitmap.bytesPerRow * bitmap.height)
        return image
    }
}
