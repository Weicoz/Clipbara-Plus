import SwiftData
import XCTest

@MainActor
final class ClipboardMonitorTests: XCTestCase {
    private var container: ModelContainer!
    private var monitor: ClipboardMonitor!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: PlusSettings.deduplicationKey)
        container = try ModelContainer(
            for: ClipboardItem.self, Pinboard.self, PinboardEntry.self, ExcludedApp.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        monitor = ClipboardMonitor()
        monitor.start(modelContext: context)
        monitor.stop() // Exercise capture without polling or writing the user's clipboard.
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: PlusSettings.deduplicationKey)
    }

    private func record(_ text: String, type: ContentType = .plainText) {
        monitor.record(.init(contentType: type, rawData: Data(text.utf8), textContent: text))
    }

    private func items() throws -> [ClipboardItem] {
        try context.fetch(FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.copiedAt, order: .reverse)]))
    }

    func testOldDuplicateMovesToTopAndKeepsTitlePinboardAndQueueCallback() throws {
        record("same")
        let original = try XCTUnwrap(items().first)
        original.copiedAt = Date(timeIntervalSince1970: 1)
        original.userTitle = "My title"
        original.isPinned = true
        let board = Pinboard(name: "Keep")
        context.insert(board)
        context.insert(PinboardEntry(clipboardItem: original, pinboard: board, displayOrder: 0))
        try context.save()
        record("different")
        var captured: ClipboardItem?
        monitor.onCapture = { captured = $0 }

        record("same")

        let saved = try items()
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(saved.first?.id, original.id)
        XCTAssertEqual(original.userTitle, "My title")
        XCTAssertTrue(original.isPinned)
        XCTAssertEqual(board.entries.first?.clipboardItem?.id, original.id)
        XCTAssertEqual(captured?.id, original.id)
        XCTAssertEqual(monitor.latestItems.first?.id, original.id)
    }

    func testDifferentFormatsAndWhitespaceStaySeparate() throws {
        record("same")
        record("same", type: .html)
        record("same ")
        XCTAssertEqual(try items().count, 3)
    }

    func testExactImageBytesDeduplicateAcrossDates() throws {
        // Image storage equality must not depend on successful thumbnail decoding.
        record("image bytes", type: .image)
        let original = try XCTUnwrap(items().first)
        original.copiedAt = Date(timeIntervalSince1970: 1)
        try context.save()
        record("image bytes", type: .image)
        record("other encoding", type: .image)
        XCTAssertEqual(try items().count, 2)
        XCTAssertTrue(try items().contains { $0.id == original.id })
    }

    func testDeduplicationCanBeDisabledAndEnabledWithoutRestart() throws {
        record("same")
        UserDefaults.standard.set(false, forKey: PlusSettings.deduplicationKey)
        record("same")
        XCTAssertEqual(try items().count, 2)

        UserDefaults.standard.set(true, forKey: PlusSettings.deduplicationKey)
        let newestID = try XCTUnwrap(items().first?.id)
        record("same")
        XCTAssertEqual(try items().count, 2)
        XCTAssertEqual(try items().first?.id, newestID)
    }
}
