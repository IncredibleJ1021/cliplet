import AppKit
import ClipCore

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

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != changeCount else {
            return
        }

        changeCount = pasteboard.changeCount

        guard let string = pasteboard.string(forType: .string),
              history.add(string) else {
            return
        }

        NotificationCenter.default.post(name: .clipboardHistoryDidChange, object: nil)
    }
}
