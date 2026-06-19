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

    private func makeDefaults() -> UserDefaults {
        let suiteName = "ClipletTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
