import Foundation

public final class ClipboardImageStore {
    public let directoryURL: URL

    private let fileManager: FileManager

    public init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    public static func applicationSupport() -> ClipboardImageStore {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directoryURL = baseURL
            .appendingPathComponent("cliplet", isDirectory: true)
            .appendingPathComponent("Images", isDirectory: true)

        return ClipboardImageStore(directoryURL: directoryURL)
    }

    public func store(
        _ data: Data,
        pasteboardType: String,
        id: UUID = UUID(),
        fingerprint: String? = nil
    ) throws -> ClipboardImage {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let key = "\(id.uuidString).\(fileExtension(for: pasteboardType))"
        let fileURL = directoryURL.appendingPathComponent(key, isDirectory: false)
        try data.write(to: fileURL, options: .atomic)

        return ClipboardImage(
            storage: .file(key),
            pasteboardType: pasteboardType,
            byteCount: data.count,
            fingerprint: fingerprint ?? data.clipletFingerprint
        )
    }

    public func data(for image: ClipboardImage) -> Data? {
        switch image.storage {
        case .inline(let data):
            return data
        case .file(let key):
            guard isSafeKey(key) else {
                return nil
            }

            return try? Data(contentsOf: directoryURL.appendingPathComponent(key, isDirectory: false))
        }
    }

    public func deleteUnused(keeping retainedKeys: Set<String>) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for fileURL in files where !retainedKeys.contains(fileURL.lastPathComponent) {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    public func removeAll() {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }

        try? fileManager.removeItem(at: directoryURL)
    }

    private func fileExtension(for pasteboardType: String) -> String {
        let lowercasedType = pasteboardType.lowercased()

        if lowercasedType.contains("png") {
            return "png"
        }
        if lowercasedType.contains("tiff") || lowercasedType.contains("tif") {
            return "tiff"
        }

        return "bin"
    }

    private func isSafeKey(_ key: String) -> Bool {
        !key.isEmpty && !key.contains("/") && !key.contains("..")
    }
}
