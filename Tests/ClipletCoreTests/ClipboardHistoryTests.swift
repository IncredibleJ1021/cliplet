import XCTest
@testable import ClipletCore

final class ClipboardHistoryTests: XCTestCase {
    func testAddsNewestItemFirst() {
        let defaults = makeDefaults()
        let history = ClipboardHistory(defaults: defaults, storageKey: "items", limit: 5)

        history.add("first")
        history.add("second")

        XCTAssertEqual(history.items.map(\.content), ["second", "first"])
    }

    func testMovesDuplicateToTop() {
        let defaults = makeDefaults()
        let history = ClipboardHistory(defaults: defaults, storageKey: "items", limit: 5)

        history.add("first")
        history.add("second")
        history.add("first")

        XCTAssertEqual(history.items.map(\.content), ["first", "second"])
    }

    func testTrimsToLimit() {
        let defaults = makeDefaults()
        let history = ClipboardHistory(defaults: defaults, storageKey: "items", limit: 2)

        history.add("one")
        history.add("two")
        history.add("three")

        XCTAssertEqual(history.items.map(\.content), ["three", "two"])
    }

    func testIgnoresBlankContent() {
        let defaults = makeDefaults()
        let history = ClipboardHistory(defaults: defaults, storageKey: "items", limit: 5)

        XCTAssertFalse(history.add("   \n"))
        XCTAssertTrue(history.items.isEmpty)
    }

    func testPersistsItems() {
        let defaults = makeDefaults()

        let firstHistory = ClipboardHistory(defaults: defaults, storageKey: "items", limit: 5)
        firstHistory.add("persisted")

        let secondHistory = ClipboardHistory(defaults: defaults, storageKey: "items", limit: 5)

        XCTAssertEqual(secondHistory.items.map(\.content), ["persisted"])
    }

    func testAddsImageItem() {
        let defaults = makeDefaults()
        let history = ClipboardHistory(defaults: defaults, storageKey: "items", limit: 5)
        let data = Data([0, 1, 2, 3])

        XCTAssertTrue(history.addImageData(data, pasteboardType: "public.png"))

        XCTAssertEqual(history.items.first?.kind, .image)
        XCTAssertEqual(history.items.first?.imageData, data)
        XCTAssertEqual(history.items.first?.imagePasteboardType, "public.png")
    }

    func testMovesDuplicateImageToTop() {
        let defaults = makeDefaults()
        let history = ClipboardHistory(defaults: defaults, storageKey: "items", limit: 5)
        let firstData = Data([0, 1, 2, 3])
        let secondData = Data([4, 5, 6, 7])

        history.addImageData(firstData, pasteboardType: "public.png")
        history.addImageData(secondData, pasteboardType: "public.png")
        history.addImageData(firstData, pasteboardType: "public.png")

        XCTAssertEqual(history.items.compactMap(\.imageData), [firstData, secondData])
    }

    func testDecodesLegacyTextItems() throws {
        struct LegacyItem: Encodable {
            let id: UUID
            let content: String
            let createdAt: Date
        }

        let defaults = makeDefaults()
        let legacyItems = [
            LegacyItem(id: UUID(), content: "legacy", createdAt: Date())
        ]
        let data = try JSONEncoder().encode(legacyItems)
        defaults.set(data, forKey: "items")

        let history = ClipboardHistory(defaults: defaults, storageKey: "items", limit: 5)

        XCTAssertEqual(history.items.first?.kind, .text)
        XCTAssertEqual(history.items.first?.content, "legacy")
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "ClipletTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
