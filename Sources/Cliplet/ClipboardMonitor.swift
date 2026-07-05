import AppKit
import ClipletCore

final class ClipboardMonitor {
    private let history: ClipboardHistory
    private var timer: Timer?
    private var changeCount = NSPasteboard.general.changeCount

    init(history: ClipboardHistory) {
        self.history = history
    }

    func start() {
        guard timer == nil else {
            return
        }

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func syncChangeCount() {
        changeCount = NSPasteboard.general.changeCount
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != changeCount else {
            return
        }

        changeCount = pasteboard.changeCount

        if let imagePayload = imagePayload(from: pasteboard),
           history.addImageData(imagePayload.data, pasteboardType: imagePayload.type.rawValue) {
            NotificationCenter.default.post(name: .clipboardHistoryDidChange, object: nil)
            return
        }

        if let string = pasteboard.string(forType: .string),
           history.add(string) {
            NotificationCenter.default.post(name: .clipboardHistoryDidChange, object: nil)
        }
    }

    private func imagePayload(from pasteboard: NSPasteboard) -> (data: Data, type: NSPasteboard.PasteboardType)? {
        if let pngData = pasteboard.data(forType: .png) {
            return (pngData, .png)
        }

        if let tiffData = pasteboard.data(forType: .tiff) {
            return (tiffData, .tiff)
        }

        guard let image = NSImage(pasteboard: pasteboard),
              let pngData = image.pngData else {
            return nil
        }

        return (pngData, .png)
    }
}

private extension NSImage {
    var pngData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}
