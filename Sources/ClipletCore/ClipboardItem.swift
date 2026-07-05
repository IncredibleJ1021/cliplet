import Foundation

public struct ClipboardItem: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable {
        case text
        case image
    }

    public enum Payload: Equatable {
        case text(String)
        case image(ClipboardImage)
    }

    public let id: UUID
    public let payload: Payload
    public let createdAt: Date

    public init(id: UUID = UUID(), content: String, createdAt: Date = Date()) {
        self.id = id
        self.payload = .text(content)
        self.createdAt = createdAt
    }

    public init(
        id: UUID = UUID(),
        image: ClipboardImage,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.payload = .image(image)
        self.createdAt = createdAt
    }

    public init(
        id: UUID = UUID(),
        imageData: Data,
        imagePasteboardType: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.payload = .image(
            ClipboardImage(
                storage: .inline(imageData),
                pasteboardType: imagePasteboardType,
                byteCount: imageData.count,
                fingerprint: imageData.clipletFingerprint
            )
        )
        self.createdAt = createdAt
    }

    public var kind: Kind {
        switch payload {
        case .text:
            .text
        case .image:
            .image
        }
    }

    public var text: String? {
        switch payload {
        case .text(let text):
            text
        case .image:
            nil
        }
    }

    public var image: ClipboardImage? {
        switch payload {
        case .text:
            nil
        case .image(let image):
            image
        }
    }

    public var imagePasteboardType: String? {
        image?.pasteboardType
    }

    public var imageStorageKey: String? {
        image?.storageKey
    }

    public var imageByteCount: Int? {
        image?.byteCount
    }

    public var imageFingerprint: String? {
        image?.fingerprint
    }

    public var content: String {
        switch payload {
        case .text(let text):
            text
        case .image:
            "Image"
        }
    }

    public var searchableText: String {
        switch payload {
        case .text(let text):
            text
        case .image:
            "image picture photo screenshot 图片 照片 截图"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case text
        case content
        case imageData
        case imageStorageKey
        case imagePasteboardType
        case imageByteCount
        case imageFingerprint
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)

        guard let decodedKind = try container.decodeIfPresent(Kind.self, forKey: .kind) else {
            payload = .text(try container.decode(String.self, forKey: .content))
            return
        }

        switch decodedKind {
        case .text:
            let decodedText = try container.decodeIfPresent(String.self, forKey: .text) ??
                container.decodeIfPresent(String.self, forKey: .content) ??
                ""
            payload = .text(decodedText)
        case .image:
            let pasteboardType = try container.decodeIfPresent(String.self, forKey: .imagePasteboardType) ?? "public.png"

            if let storageKey = try container.decodeIfPresent(String.self, forKey: .imageStorageKey) {
                payload = .image(
                    ClipboardImage(
                        storage: .file(storageKey),
                        pasteboardType: pasteboardType,
                        byteCount: try container.decodeIfPresent(Int.self, forKey: .imageByteCount) ?? 0,
                        fingerprint: try container.decodeIfPresent(String.self, forKey: .imageFingerprint) ?? ""
                    )
                )
            } else if let imageData = try container.decodeIfPresent(Data.self, forKey: .imageData) {
                payload = .image(
                    ClipboardImage(
                        storage: .inline(imageData),
                        pasteboardType: pasteboardType,
                        byteCount: imageData.count,
                        fingerprint: imageData.clipletFingerprint
                    )
                )
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .kind,
                    in: container,
                    debugDescription: "Image clipboard item has no file key or inline data."
                )
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(createdAt, forKey: .createdAt)

        switch payload {
        case .text(let text):
            try container.encode(text, forKey: .text)
            try container.encode(text, forKey: .content)
        case .image(let image):
            try container.encode(image.pasteboardType, forKey: .imagePasteboardType)
            try container.encode(image.byteCount, forKey: .imageByteCount)
            try container.encode(image.fingerprint, forKey: .imageFingerprint)

            switch image.storage {
            case .file(let key):
                try container.encode(key, forKey: .imageStorageKey)
            case .inline(let data):
                try container.encode(data, forKey: .imageData)
            }
        }
    }
}

public struct ClipboardImage: Equatable {
    public enum Storage: Equatable {
        case file(String)
        case inline(Data)
    }

    public let storage: Storage
    public let pasteboardType: String
    public let byteCount: Int
    public let fingerprint: String

    public init(storage: Storage, pasteboardType: String, byteCount: Int, fingerprint: String) {
        self.storage = storage
        self.pasteboardType = pasteboardType
        self.byteCount = byteCount
        self.fingerprint = fingerprint
    }

    public var storageKey: String? {
        switch storage {
        case .file(let key):
            key
        case .inline:
            nil
        }
    }

    public var inlineData: Data? {
        switch storage {
        case .file:
            nil
        case .inline(let data):
            data
        }
    }
}

extension Data {
    var clipletFingerprint: String {
        var hash: UInt64 = 14_695_981_039_346_656_037

        for byte in self {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }

        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: Swift.max(0, 16 - hex.count)) + hex
    }
}
