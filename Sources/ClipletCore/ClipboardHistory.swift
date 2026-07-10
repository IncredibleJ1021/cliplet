import Foundation

public final class ClipboardHistory {
    public private(set) var items: [ClipboardItem]
    public private(set) var limit: Int

    private let defaults: UserDefaults
    private let storageKey: String
    private let imageStore: ClipboardImageStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "clipboard.history.items",
        limit: Int = 50,
        imageStore: ClipboardImageStore = .applicationSupport()
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.imageStore = imageStore
        self.limit = Self.clampedLimit(limit)
        self.items = []

        if let data = defaults.data(forKey: storageKey),
           let decodedItems = try? decoder.decode([ClipboardItem].self, from: data) {
            var didChangeStoredForm = false
            self.items = decodedItems.map { item in
                let prepared = prepareForFileStorage(item)
                didChangeStoredForm = didChangeStoredForm || prepared.didChange
                return prepared.item
            }

            if items.count > self.limit {
                self.items = Array(items.prefix(self.limit))
                didChangeStoredForm = true
            }

            if didChangeStoredForm {
                persistAndPruneImages()
            }
        }
    }

    @discardableResult
    public func add(_ content: String, createdAt: Date = Date()) -> Bool {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        if let existing = items.first(where: { $0.text == content }) {
            return promote(existing.id, createdAt: createdAt)
        }

        items.insert(ClipboardItem(content: content, createdAt: createdAt), at: 0)
        trimToLimit()
        persistAndPruneImages()
        return true
    }

    @discardableResult
    public func promote(_ id: UUID, createdAt: Date = Date()) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let existing = items.remove(at: index)
        let promoted: ClipboardItem
        switch existing.payload {
        case .text(let text):
            promoted = ClipboardItem(id: existing.id, content: text, createdAt: createdAt)
        case .image(let image):
            promoted = ClipboardItem(id: existing.id, image: image, createdAt: createdAt)
        }

        items.insert(promoted, at: 0)
        persistAndPruneImages()
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

        let fingerprint = imageData.clipletFingerprint
        if let existing = items.first(where: {
            $0.imagePasteboardType == pasteboardType &&
                $0.imageByteCount == imageData.count &&
                $0.imageFingerprint == fingerprint
        }), self.imageData(for: existing) == imageData {
            return promote(existing.id, createdAt: createdAt)
        }

        let id = UUID()
        let image: ClipboardImage
        do {
            image = try imageStore.store(
                imageData,
                pasteboardType: pasteboardType,
                id: id,
                fingerprint: fingerprint
            )
        } catch {
            return false
        }

        items.insert(ClipboardItem(id: id, image: image, createdAt: createdAt), at: 0)
        trimToLimit()
        persistAndPruneImages()
        return true
    }

    public func imageData(for item: ClipboardItem) -> Data? {
        guard let image = item.image else {
            return nil
        }

        return imageStore.data(for: image)
    }

    public func updateLimit(_ newLimit: Int) {
        limit = Self.clampedLimit(newLimit)
        trimToLimit()
        persistAndPruneImages()
    }

    public func clear() {
        items.removeAll()
        if save() {
            imageStore.removeAll()
        }
    }

    private func trimToLimit() {
        if items.count > limit {
            items = Array(items.prefix(limit))
        }
    }

    private func prepareForFileStorage(_ item: ClipboardItem) -> (item: ClipboardItem, didChange: Bool) {
        guard let image = item.image,
              let inlineData = image.inlineData else {
            return (item, false)
        }

        do {
            let storedImage = try imageStore.store(inlineData, pasteboardType: image.pasteboardType, id: item.id)
            return (ClipboardItem(id: item.id, image: storedImage, createdAt: item.createdAt), true)
        } catch {
            return (item, false)
        }
    }

    private func persistAndPruneImages() {
        guard save() else {
            return
        }

        imageStore.deleteUnused(keeping: retainedImageKeys())
    }

    private func retainedImageKeys() -> Set<String> {
        Set(items.compactMap(\.imageStorageKey))
    }

    @discardableResult
    private func save() -> Bool {
        guard let data = try? encoder.encode(items) else {
            return false
        }

        defaults.set(data, forKey: storageKey)
        return true
    }

    private static func clampedLimit(_ value: Int) -> Int {
        min(max(value, 1), 200)
    }
}
