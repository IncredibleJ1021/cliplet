import AppKit
import XCTest
@testable import Cliplet
@testable import ClipletCore

final class ClipboardSelectionServiceTests: XCTestCase {
    func testWriteFailureDoesNotPromoteOrSyncHistory() {
        let history = makeHistory()
        history.add("first")
        history.add("second")
        let first = history.items.last!
        let writer = WriterStub(textResult: false, imageResult: false)
        var syncCount = 0
        let service = ClipboardSelectionService(
            history: history,
            writer: writer,
            onPasteboardWrite: { syncCount += 1 }
        )

        XCTAssertEqual(service.copy(first), .pasteboardWriteFailed)
        XCTAssertEqual(history.items.map(\.text), ["second", "first"])
        XCTAssertEqual(syncCount, 0)
    }

    func testSuccessfulTextWritePromotesAndSyncsOnce() {
        let history = makeHistory()
        history.add("first")
        history.add("second")
        let first = history.items.last!
        let writer = WriterStub(textResult: true, imageResult: true)
        var syncCount = 0
        let service = ClipboardSelectionService(
            history: history,
            writer: writer,
            onPasteboardWrite: { syncCount += 1 }
        )

        XCTAssertEqual(service.copy(first), .copied(historyChanged: true))
        XCTAssertEqual(writer.writtenText, "first")
        XCTAssertEqual(history.items.first?.id, first.id)
        XCTAssertEqual(syncCount, 1)
    }

    func testImageWriteFailureDoesNotPromoteOrSyncHistory() {
        let history = makeHistory()
        history.addImageData(Data([0, 1, 2, 3]), pasteboardType: "public.png")
        let image = history.items.first!
        history.add("newer text")
        let writer = WriterStub(textResult: true, imageResult: false)
        var syncCount = 0
        let service = ClipboardSelectionService(
            history: history,
            writer: writer,
            onPasteboardWrite: { syncCount += 1 }
        )

        XCTAssertEqual(service.copy(image), .pasteboardWriteFailed)
        XCTAssertEqual(history.items.last?.id, image.id)
        XCTAssertEqual(syncCount, 0)
    }

    private func makeHistory() -> ClipboardHistory {
        let suite = "ClipletSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(suite, isDirectory: true)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        return ClipboardHistory(
            defaults: defaults,
            storageKey: "items",
            limit: 5,
            imageStore: ClipboardImageStore(directoryURL: directory)
        )
    }
}

private final class WriterStub: ClipboardWriting {
    let textResult: Bool
    let imageResult: Bool
    var writtenText: String?

    init(textResult: Bool, imageResult: Bool) {
        self.textResult = textResult
        self.imageResult = imageResult
    }

    func writeText(_ text: String) -> Bool {
        writtenText = text
        return textResult
    }

    func writeImage(_ data: Data, pasteboardType: String) -> Bool {
        imageResult
    }
}
