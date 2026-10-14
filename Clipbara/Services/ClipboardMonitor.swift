import AppKit
import SwiftData
import CryptoKit

@MainActor
@Observable
final class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let classifier = ContentTypeClassifier()
    private var modelContext: ModelContext?
    private var excludedBundleIds: Set<String> = []
    private var shouldSkipNextChange: Bool = false

    var isMonitoring: Bool = false
    /// Called with every copy Clipbara records, including one that matched a
    /// clip copied moments earlier. The Clip Queue collects from here.
    @ObservationIgnored var onCapture: ((ClipboardItem) -> Void)?
    var latestItems: [ClipboardItem] = []
    var historyLimit: Int {
        get { UserDefaults.standard.object(forKey: "historyLimit") as? Int ?? 500 }
        set { UserDefaults.standard.set(newValue, forKey: "historyLimit") }
    }

    func start(modelContext: ModelContext) {
        self.modelContext = modelContext
        lastChangeCount = NSPasteboard.general.changeCount
        loadExcludedApps()
        isMonitoring = true

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
    }

    func toggle() {
        if isMonitoring { stop() } else if let ctx = modelContext { start(modelContext: ctx) }
    }

    func refreshLatestItems() {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.copiedAt, order: .reverse)]
        )
        var limited = descriptor
        limited.fetchLimit = 5
        latestItems = (try? modelContext.fetch(limited)) ?? []
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount

        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        if shouldSkipNextChange {
            shouldSkipNextChange = false
            return
        }

        // Check excluded apps
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           let bundleId = frontApp.bundleIdentifier,
           excludedBundleIds.contains(bundleId) {
            return
        }

        guard let content = classifier.classify(pasteboard) else { return }

        record(content)
    }

    func record(_ content: ContentTypeClassifier.ClassifiedContent) {
        guard let modelContext else { return }

        let hash = SHA256.hash(data: content.rawData)
            .compactMap { String(format: "%02x", $0) }
            .joined()

        // Reuse history across all dates without losing titles or pinboard entries.
        if PlusSettings.automaticDeduplication,
           let existing = duplicate(hash: hash, contentType: content.contentType) {
            existing.copiedAt = Date()
            try? modelContext.save()
            refreshLatestItems()
            onCapture?(existing)
            return
        }

        let sourceApp = NSWorkspace.shared.frontmostApplication
        let item = ClipboardItem(
            contentType: content.contentType,
            rawData: content.rawData,
            textContent: content.textContent,
            sourceAppName: sourceApp?.localizedName,
            sourceAppBundleId: sourceApp?.bundleIdentifier,
            contentHash: hash
        )

        // Generate thumbnail for images
        if content.contentType == .image {
            item.thumbnailData = ImageThumbnail.png(from: content.rawData, lowMemory: PlusSettings.lowMemoryImages)
        }

        modelContext.insert(item)
        try? modelContext.save()
        cleanupOldItems()
        refreshLatestItems()
        onCapture?(item)
    }

    /// 히스토리 제한 초과 시 오래된 아이템 삭제 (isPinned 아이템 보존)
    private func cleanupOldItems() {
        guard let modelContext, historyLimit > 0 else { return }

        let countDescriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned }
        )
        let unpinnedCount = (try? modelContext.fetchCount(countDescriptor)) ?? 0

        guard unpinnedCount > historyLimit else { return }

        let deleteCount = unpinnedCount - historyLimit
        var fetchDescriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned },
            sortBy: [SortDescriptor(\.copiedAt, order: .forward)]
        )
        fetchDescriptor.fetchLimit = deleteCount

        guard let itemsToDelete = try? modelContext.fetch(fetchDescriptor) else { return }

        for item in itemsToDelete {
            // 연관 PinboardEntry 제거
            let itemId = item.id
            let entryDescriptor = FetchDescriptor<PinboardEntry>(
                predicate: #Predicate { $0.clipboardItem?.id == itemId }
            )
            if let entries = try? modelContext.fetch(entryDescriptor) {
                for entry in entries {
                    modelContext.delete(entry)
                }
            }
            modelContext.delete(item)
        }
        try? modelContext.save()
    }

    private func duplicate(hash: String, contentType: ContentType) -> ClipboardItem? {
        guard let modelContext else { return nil }
        let type = contentType.rawValue
        let predicate = #Predicate<ClipboardItem> { item in
            item.contentHash == hash && item.contentTypeRaw == type
        }
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.copiedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func skipNextChange() {
        shouldSkipNextChange = true
    }

    func loadExcludedApps() {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<ExcludedApp>()
        let apps = (try? modelContext.fetch(descriptor)) ?? []
        excludedBundleIds = Set(apps.map(\.bundleId))
    }
}
