import AppKit
import ApplicationServices

enum AutoPasteResult: Equatable {
    case pasted
    case accessibilityDenied
    case targetUnavailable
    case activationFailed
    case activationTimedOut
    case eventPostingFailed
}

struct AutoPasteEnvironment {
    let isTrusted: () -> Bool
    let isApplicationAvailable: (NSRunningApplication) -> Bool
    let activate: (NSRunningApplication) -> Bool
    let frontmostPID: () -> pid_t?
    let postCommandV: () -> Bool
    let schedule: (TimeInterval, @escaping () -> Void) -> Void

    static let live = AutoPasteEnvironment(
        isTrusted: { AXIsProcessTrusted() },
        isApplicationAvailable: { !$0.isTerminated },
        activate: { application in
            if #available(macOS 14, *) {
                return application.activate()
            }
            return application.activate(options: [.activateIgnoringOtherApps])
        },
        frontmostPID: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
        postCommandV: AutoPasteController.postCommandV,
        schedule: { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
        }
    )
}

final class AutoPasteController {
    private static let pasteKeyCode: CGKeyCode = 9
    private let environment: AutoPasteEnvironment
    private let activationTimeout: TimeInterval
    private let pollInterval: TimeInterval

    init(
        environment: AutoPasteEnvironment = .live,
        activationTimeout: TimeInterval = 0.5,
        pollInterval: TimeInterval = 0.02
    ) {
        self.environment = environment
        self.activationTimeout = activationTimeout
        self.pollInterval = pollInterval
    }

    var isAccessibilityTrusted: Bool {
        environment.isTrusted()
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

    func paste(
        to application: NSRunningApplication?,
        completion: @escaping (AutoPasteResult) -> Void
    ) {
        guard environment.isTrusted() else {
            completion(.accessibilityDenied)
            return
        }
        guard let application, environment.isApplicationAvailable(application) else {
            completion(.targetUnavailable)
            return
        }
        guard environment.activate(application) else {
            completion(.activationFailed)
            return
        }

        waitForActivation(of: application, elapsed: 0, completion: completion)
    }

    private func waitForActivation(
        of application: NSRunningApplication,
        elapsed: TimeInterval,
        completion: @escaping (AutoPasteResult) -> Void
    ) {
        guard environment.isApplicationAvailable(application) else {
            completion(.targetUnavailable)
            return
        }
        if environment.frontmostPID() == application.processIdentifier {
            completion(environment.postCommandV() ? .pasted : .eventPostingFailed)
            return
        }
        guard elapsed < activationTimeout else {
            completion(.activationTimedOut)
            return
        }

        environment.schedule(pollInterval) { [weak self, weak application] in
            guard let self, let application else {
                completion(.targetUnavailable)
                return
            }
            self.waitForActivation(
                of: application,
                elapsed: elapsed + self.pollInterval,
                completion: completion
            )
        }
    }

    fileprivate static func postCommandV() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: pasteKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: pasteKeyCode, keyDown: false) else {
            return false
        }

        keyDown.flags = [.maskCommand]
        keyUp.flags = [.maskCommand]
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
