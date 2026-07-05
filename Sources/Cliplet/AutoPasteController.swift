import AppKit
import ApplicationServices

final class AutoPasteController {
    private let pasteKeyCode: CGKeyCode = 9
    private let pasteDelay: TimeInterval = 0.12

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func requestAccessibilityPermissionPrompt() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    @discardableResult
    func paste(to application: NSRunningApplication?) -> Bool {
        guard isAccessibilityTrusted else {
            return false
        }

        activate(application)
        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) { [pasteKeyCode] in
            Self.postCommandV(keyCode: pasteKeyCode)
        }
        return true
    }

    private func activate(_ application: NSRunningApplication?) {
        guard let application else {
            return
        }

        if #available(macOS 14, *) {
            application.activate()
        } else {
            application.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private static func postCommandV(keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)

        keyDown?.flags = [.maskCommand]
        keyUp?.flags = [.maskCommand]
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
