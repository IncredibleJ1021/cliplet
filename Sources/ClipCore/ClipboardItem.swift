import Foundation

public struct ClipboardItem: Codable, Equatable, Identifiable {
    public let id: UUID
    public let content: String
    public let createdAt: Date

    public init(id: UUID = UUID(), content: String, createdAt: Date = Date()) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
    }
}
