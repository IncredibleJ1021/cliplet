import AppKit
import ClipletCore

protocol ClipboardWriting {
    func writeText(_ text: String) -> Bool
    func writeImage(_ data: Data, pasteboardType: String) -> Bool
}

final class SystemClipboardWriter: ClipboardWriting {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func writeText(_ text: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    func writeImage(_ data: Data, pasteboardType: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setData(data, forType: NSPasteboard.PasteboardType(pasteboardType))
    }
}

enum ClipboardSelectionResult: Equatable {
    case copied(historyChanged: Bool)
    case itemUnavailable
    case pasteboardWriteFailed
}

final class ClipboardSelectionService {
    private let history: ClipboardHistory
    private let writer: ClipboardWriting
    private let onPasteboardWrite: () -> Void

    init(
        history: ClipboardHistory,
        writer: ClipboardWriting = SystemClipboardWriter(),
        onPasteboardWrite: @escaping () -> Void = {}
    ) {
        self.history = history
        self.writer = writer
        self.onPasteboardWrite = onPasteboardWrite
    }

    func copy(_ item: ClipboardItem) -> ClipboardSelectionResult {
        let didWrite: Bool
        switch item.payload {
        case .text(let text):
            didWrite = writer.writeText(text)
        case .image:
            guard let data = history.imageData(for: item),
                  let pasteboardType = item.imagePasteboardType else {
                return .itemUnavailable
            }
            didWrite = writer.writeImage(data, pasteboardType: pasteboardType)
        }

        guard didWrite else {
            return .pasteboardWriteFailed
        }

        let historyChanged = history.promote(item.id)
        onPasteboardWrite()
        return .copied(historyChanged: historyChanged)
    }
}
