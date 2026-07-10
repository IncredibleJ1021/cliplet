import Foundation

enum HistoryLimitInput {
    static let supportedRange = 1...200

    static func parse(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let parsed = Int(trimmed),
              supportedRange.contains(parsed) else {
            return nil
        }
        return parsed
    }
}
