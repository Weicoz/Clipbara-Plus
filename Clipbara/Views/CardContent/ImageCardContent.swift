import SwiftUI
import AppKit

struct ImageCardContent: View {
    let item: ClipboardItem
    @State private var cachedImage: NSImage?
    @AppStorage(PlusSettings.lowMemoryImagesKey) private var lowMemoryImages = true

    var body: some View {
        Group {
            if let image = cachedImage {
                ZStack {
                    CheckerboardPattern()
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(item.id)-\(lowMemoryImages)") {
            cachedImage = ThumbnailImageCache.image(for: item)
        }
    }
}

// MARK: - Checkerboard Pattern

private struct CheckerboardPattern: View {
    private let cellSize = DesignTokens.Checkerboard.cellSize

    var body: some View {
        Canvas { context, size in
            let cols = Int(ceil(size.width / cellSize))
            let rows = Int(ceil(size.height / cellSize))

            // Fill with light color first
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(DesignTokens.Checkerboard.lightColor)
            )

            // Draw dark cells
            for row in 0..<rows {
                for col in 0..<cols where (row + col).isMultiple(of: 2) {
                    let rect = CGRect(
                        x: CGFloat(col) * cellSize,
                        y: CGFloat(row) * cellSize,
                        width: cellSize,
                        height: cellSize
                    )
                    context.fill(Path(rect), with: .color(DesignTokens.Checkerboard.darkColor))
                }
            }
        }
    }
}
