import Foundation

public final class ClipboardHistory {
    public private(set) var items: [ClipboardItem]
    public private(set) var limit: Int

    private let defaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "clipboard.history.items",
        limit: Int = 50
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.limit = Self.clampedLimit(limit)

        if let data = defaults.data(forKey: storageKey),
           let decodedItems = try? decoder.decode([ClipboardItem].self, from: data) {
            self.items = Array(decodedItems.prefix(self.limit))
        } else {
            self.items = []
        }
    }

    @discardableResult
    public func add(_ content: String, createdAt: Date = Date()) -> Bool {
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return false
        }

        items.removeAll { $0.kind == .text && $0.text == normalized }
        items.insert(ClipboardItem(content: normalized, createdAt: createdAt), at: 0)
        trimToLimit()
        save()
        return true
    }

    @discardableResult
    public func addImageData(
        _ imageData: Data,
        pasteboardType: String,
        createdAt: Date = Date()
    ) -> Bool {
        guard !imageData.isEmpty else {
            return false
        }

        items.removeAll {
            $0.kind == .image &&
                $0.imageData == imageData &&
                $0.imagePasteboardType == pasteboardType
        }
        items.insert(
            ClipboardItem(
                imageData: imageData,
                imagePasteboardType: pasteboardType,
                createdAt: createdAt
            ),
            at: 0
        )
        trimToLimit()
        save()
        return true
    }

    public func updateLimit(_ newLimit: Int) {
        limit = Self.clampedLimit(newLimit)
        trimToLimit()
        save()
    }

    public func clear() {
        items.removeAll()
        save()
    }

    private func trimToLimit() {
        if items.count > limit {
            items = Array(items.prefix(limit))
        }
    }

    private func save() {
        guard let data = try? encoder.encode(items) else {
            return
        }

        defaults.set(data, forKey: storageKey)
    }

    private static func clampedLimit(_ value: Int) -> Int {
        min(max(value, 1), 200)
    }
}
