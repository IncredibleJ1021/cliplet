import Foundation

public struct ClipboardItem: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable {
        case text
        case image
    }

    public let id: UUID
    public let kind: Kind
    public let text: String?
    public let imageData: Data?
    public let imagePasteboardType: String?
    public let createdAt: Date

    public init(id: UUID = UUID(), content: String, createdAt: Date = Date()) {
        self.id = id
        self.kind = .text
        self.text = content
        self.imageData = nil
        self.imagePasteboardType = nil
        self.createdAt = createdAt
    }

    public init(
        id: UUID = UUID(),
        imageData: Data,
        imagePasteboardType: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = .image
        self.text = nil
        self.imageData = imageData
        self.imagePasteboardType = imagePasteboardType
        self.createdAt = createdAt
    }

    public var content: String {
        switch kind {
        case .text:
            text ?? ""
        case .image:
            "Image"
        }
    }

    public var searchableText: String {
        switch kind {
        case .text:
            text ?? ""
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
        case imagePasteboardType
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)

        if let decodedKind = try container.decodeIfPresent(Kind.self, forKey: .kind) {
            kind = decodedKind
            text = try container.decodeIfPresent(String.self, forKey: .text)
            imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
            imagePasteboardType = try container.decodeIfPresent(String.self, forKey: .imagePasteboardType)
        } else {
            kind = .text
            text = try container.decode(String.self, forKey: .content)
            imageData = nil
            imagePasteboardType = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(createdAt, forKey: .createdAt)

        switch kind {
        case .text:
            try container.encode(text ?? "", forKey: .text)
            try container.encode(text ?? "", forKey: .content)
        case .image:
            try container.encodeIfPresent(imageData, forKey: .imageData)
            try container.encodeIfPresent(imagePasteboardType, forKey: .imagePasteboardType)
        }
    }
}
