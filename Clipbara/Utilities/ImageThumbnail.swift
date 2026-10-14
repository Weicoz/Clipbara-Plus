import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageThumbnail {
    static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        // Downsample at decode time; never render a full-sized image for a card.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 320,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func png(from data: Data, lowMemory: Bool = true) -> Data? {
        if !lowMemory {
            guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
            let scale = min(320 / image.size.width, 320 / image.size.height, 1)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            let thumbnail = NSImage(size: size)
            thumbnail.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: size))
            thumbnail.unlockFocus()
            guard let tiff = thumbnail.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
            return bitmap.representation(using: .png, properties: [:])
        }
        guard let image = image(from: data) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
