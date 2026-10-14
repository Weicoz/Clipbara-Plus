import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest

@MainActor
final class ImageThumbnailTests: XCTestCase {
    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: PlusSettings.lowMemoryImagesKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: PlusSettings.lowMemoryImagesKey)
    }
    private func picture(width: Int, height: Int) throws -> Data {
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 0.5)
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(bitmap.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    func testLargeImageAndCacheFallbackAreBoundedWithoutChangingOriginal() throws {
        let data = try picture(width: 4096, height: 2048)
        let thumbnail = try XCTUnwrap(ImageThumbnail.png(from: data))
        let decoded = try XCTUnwrap(ImageThumbnail.image(from: thumbnail))
        XCTAssertEqual(decoded.width, 320)
        XCTAssertEqual(decoded.height, 160)
        XCTAssertLessThanOrEqual(decoded.bytesPerRow * decoded.height, 320 * 160 * 4)
        let pixel = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        pixel.draw(decoded, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let alpha = try XCTUnwrap(pixel.data).assumingMemoryBound(to: UInt8.self)[3]
        XCTAssertEqual(Int(alpha), 128, accuracy: 1)

        let item = ClipboardItem(contentType: .image, rawData: data, contentHash: "large")
        let image = try XCTUnwrap(ThumbnailImageCache.image(for: item))
        let cached = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(cached.width, 320)
        XCTAssertEqual(cached.height, 160)
        XCTAssertEqual(item.rawData, data)
        XCTAssertTrue(ThumbnailImageCache.image(for: item) === image)
    }

    func testSmallImageDoesNotUpscaleAndInvalidDataReturnsNil() throws {
        let small = try XCTUnwrap(ImageThumbnail.image(from: picture(width: 32, height: 16)))
        XCTAssertEqual(small.width, 32)
        XCTAssertEqual(small.height, 16)
        XCTAssertNil(ImageThumbnail.image(from: Data("invalid".utf8)))
        XCTAssertNil(ImageThumbnail.png(from: Data()))
    }

    func testSwitchingMemoryModeReplacesCachedImageWithoutChangingOriginal() throws {
        let data = try picture(width: 1024, height: 512)
        let item = ClipboardItem(contentType: .image, rawData: data, contentHash: "switch")
        let small = try XCTUnwrap(ThumbnailImageCache.image(for: item))
        XCTAssertEqual(small.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width, 320)

        UserDefaults.standard.set(false, forKey: PlusSettings.lowMemoryImagesKey)
        let full = try XCTUnwrap(ThumbnailImageCache.image(for: item))
        XCTAssertEqual(full.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width, 1024)
        XCTAssertFalse(small === full)
        XCTAssertNotNil(ImageThumbnail.png(from: data, lowMemory: false))

        UserDefaults.standard.set(true, forKey: PlusSettings.lowMemoryImagesKey)
        let smallAgain = try XCTUnwrap(ThumbnailImageCache.image(for: item))
        XCTAssertEqual(smallAgain.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width, 320)
        XCTAssertEqual(item.rawData, data)
    }
}
