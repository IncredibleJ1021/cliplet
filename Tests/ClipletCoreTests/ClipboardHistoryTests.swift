import XCTest
@testable import ClipletCore

final class ClipboardHistoryTests: XCTestCase {
    func testAddsNewestItemFirst() {
        let defaults = makeDefaults()
        let history = makeHistory(defaults: defaults, limit: 5)

        history.add("first")
        history.add("second")

        XCTAssertEqual(history.items.map(\.content), ["second", "first"])
    }

    func testMovesDuplicateToTop() {
        let defaults = makeDefaults()
        let history = makeHistory(defaults: defaults, limit: 5)

        history.add("first")
        history.add("second")
        history.add("first")

        XCTAssertEqual(history.items.map(\.content), ["first", "second"])
    }

    func testPromotesExistingTextItemWithoutChangingID() {
        let defaults = makeDefaults()
        let history = makeHistory(defaults: defaults, limit: 5)
        let promotedAt = Date(timeIntervalSince1970: 123)

        history.add("first")
        history.add("second")
        let firstID = history.items.last!.id

        XCTAssertTrue(history.promote(firstID, createdAt: promotedAt))
        XCTAssertEqual(history.items.first?.id, firstID)
        XCTAssertEqual(history.items.first?.text, "first")
        XCTAssertEqual(history.items.first?.createdAt, promotedAt)
    }

    func testTrimsToLimit() {
        let defaults = makeDefaults()
        let history = makeHistory(defaults: defaults, limit: 2)

        history.add("one")
        history.add("two")
        history.add("three")

        XCTAssertEqual(history.items.map(\.content), ["three", "two"])
    }

    func testIgnoresBlankContent() {
        let defaults = makeDefaults()
        let history = makeHistory(defaults: defaults, limit: 5)

        XCTAssertFalse(history.add("   \n"))
        XCTAssertTrue(history.items.isEmpty)
    }

    func testPreservesTextWhitespace() {
        let defaults = makeDefaults()
        let history = makeHistory(defaults: defaults, limit: 5)
        let content = "  copied text\n"

        XCTAssertTrue(history.add(content))

        XCTAssertEqual(history.items.first?.text, content)
    }

    func testPersistsItems() {
        let defaults = makeDefaults()
        let imageStore = makeImageStore()

        let firstHistory = ClipboardHistory(defaults: defaults, storageKey: "items", limit: 5, imageStore: imageStore)
        firstHistory.add("persisted")

        let secondHistory = ClipboardHistory(defaults: defaults, storageKey: "items", limit: 5, imageStore: imageStore)

        XCTAssertEqual(secondHistory.items.map(\.content), ["persisted"])
    }

    func testAddsImageItem() {
        let defaults = makeDefaults()
        let history = makeHistory(defaults: defaults, limit: 5)
        let data = Data([0, 1, 2, 3])

        XCTAssertTrue(history.addImageData(data, pasteboardType: "public.png"))

        XCTAssertEqual(history.items.first?.kind, .image)
        XCTAssertEqual(history.items.first.flatMap { history.imageData(for: $0) }, data)
        XCTAssertEqual(history.items.first?.imagePasteboardType, "public.png")
        XCTAssertNotNil(history.items.first?.imageStorageKey)
    }

    func testMovesDuplicateImageToTop() {
        let defaults = makeDefaults()
        let history = makeHistory(defaults: defaults, limit: 5)
        let firstData = Data([0, 1, 2, 3])
        let secondData = Data([4, 5, 6, 7])

        history.addImageData(firstData, pasteboardType: "public.png")
        history.addImageData(secondData, pasteboardType: "public.png")
        history.addImageData(firstData, pasteboardType: "public.png")

        XCTAssertEqual(history.items.compactMap { history.imageData(for: $0) }, [firstData, secondData])
    }

    func testPromotesExistingImageWithoutCreatingAnotherFile() throws {
        let defaults = makeDefaults()
        let imageStore = makeImageStore()
        let history = ClipboardHistory(defaults: defaults, storageKey: "items", limit: 5, imageStore: imageStore)
        let data = Data([0, 1, 2, 3])

        history.addImageData(data, pasteboardType: "public.png")
        let original = history.items[0]
        let originalKey = original.imageStorageKey

        XCTAssertTrue(history.promote(original.id, createdAt: Date(timeIntervalSince1970: 456)))
        XCTAssertEqual(history.items.first?.imageStorageKey, originalKey)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: imageStore.directoryURL.path).count, 1)
    }

    func testAddingDuplicateImageReusesExistingFile() throws {
        let defaults = makeDefaults()
        let imageStore = makeImageStore()
        let history = ClipboardHistory(defaults: defaults, storageKey: "items", limit: 5, imageStore: imageStore)
        let data = Data([0, 1, 2, 3])

        history.addImageData(data, pasteboardType: "public.png")
        let originalKey = history.items.first?.imageStorageKey
        history.addImageData(data, pasteboardType: "public.png")

        XCTAssertEqual(history.items.count, 1)
        XCTAssertEqual(history.items.first?.imageStorageKey, originalKey)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: imageStore.directoryURL.path).count, 1)
    }

    func testFingerprintCandidateRequiresExactByteEquality() throws {
        let defaults = makeDefaults()
        let imageStore = makeImageStore()
        let newData = Data([9, 8, 7, 6])
        let storedData = Data([1, 2, 3, 4])
        let key = "collision.png"
        try FileManager.default.createDirectory(at: imageStore.directoryURL, withIntermediateDirectories: true)
        try storedData.write(to: imageStore.directoryURL.appendingPathComponent(key))

        let existing = ClipboardItem(
            image: ClipboardImage(
                storage: .file(key),
                pasteboardType: "public.png",
                byteCount: newData.count,
                fingerprint: newData.clipletFingerprint
            )
        )
        defaults.set(try JSONEncoder().encode([existing]), forKey: "items")
        let history = ClipboardHistory(defaults: defaults, storageKey: "items", limit: 5, imageStore: imageStore)

        XCTAssertTrue(history.addImageData(newData, pasteboardType: "public.png"))
        XCTAssertEqual(history.items.count, 2)
        XCTAssertEqual(history.items.first.flatMap { history.imageData(for: $0) }, newData)
    }

    func testRemovesPrunedImageFiles() {
        let defaults = makeDefaults()
        let imageStore = makeImageStore()
        let history = ClipboardHistory(defaults: defaults, storageKey: "items", limit: 2, imageStore: imageStore)
        let firstData = Data([0, 1, 2, 3])
        let secondData = Data([4, 5, 6, 7])

        history.addImageData(firstData, pasteboardType: "public.png")
        let firstKey = history.items.first?.imageStorageKey
        history.addImageData(secondData, pasteboardType: "public.png")

        history.updateLimit(1)

        XCTAssertEqual(history.items.count, 1)
        XCTAssertEqual(history.items.first.flatMap { history.imageData(for: $0) }, secondData)
        XCTAssertFalse(fileExists(firstKey, in: imageStore))
    }

    func testMigratesLegacyImageDataToFileStorage() throws {
        struct LegacyImageItem: Encodable {
            let id: UUID
            let kind = ClipboardItem.Kind.image
            let imageData: Data
            let imagePasteboardType: String
            let createdAt: Date
        }

        let defaults = makeDefaults()
        let imageStore = makeImageStore()
        let legacyData = Data([0, 1, 2, 3])
        let legacyItems = [
            LegacyImageItem(
                id: UUID(),
                imageData: legacyData,
                imagePasteboardType: "public.png",
                createdAt: Date()
            )
        ]
        let data = try JSONEncoder().encode(legacyItems)
        defaults.set(data, forKey: "items")

        let history = ClipboardHistory(defaults: defaults, storageKey: "items", limit: 5, imageStore: imageStore)

        XCTAssertEqual(history.items.first?.kind, .image)
        XCTAssertNotNil(history.items.first?.imageStorageKey)
        XCTAssertEqual(history.items.first.flatMap { history.imageData(for: $0) }, legacyData)
    }

    func testDecodesLegacyTextItems() throws {
        struct LegacyItem: Encodable {
            let id: UUID
            let content: String
            let createdAt: Date
        }

        let defaults = makeDefaults()
        let imageStore = makeImageStore()
        let legacyItems = [
            LegacyItem(id: UUID(), content: "legacy", createdAt: Date())
        ]
        let data = try JSONEncoder().encode(legacyItems)
        defaults.set(data, forKey: "items")

        let history = ClipboardHistory(defaults: defaults, storageKey: "items", limit: 5, imageStore: imageStore)

        XCTAssertEqual(history.items.first?.kind, .text)
        XCTAssertEqual(history.items.first?.content, "legacy")
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "ClipletTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeHistory(defaults: UserDefaults, limit: Int) -> ClipboardHistory {
        ClipboardHistory(defaults: defaults, storageKey: "items", limit: limit, imageStore: makeImageStore())
    }

    private func makeImageStore() -> ClipboardImageStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ClipletTests.\(UUID().uuidString)", isDirectory: true)

        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }

        return ClipboardImageStore(directoryURL: url)
    }

    private func fileExists(_ key: String?, in imageStore: ClipboardImageStore) -> Bool {
        guard let key else {
            return false
        }

        return FileManager.default.fileExists(atPath: imageStore.directoryURL.appendingPathComponent(key).path)
    }
}
