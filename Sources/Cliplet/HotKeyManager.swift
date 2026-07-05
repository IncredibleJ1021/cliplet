import Carbon
import ClipletCore
import Foundation

enum HotKeyRegistrationError: Error, LocalizedError {
    case eventHandlerUnavailable(OSStatus)
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .eventHandlerUnavailable(let status):
            "Global shortcut event handling is unavailable. Carbon status: \(status)."
        case .registrationFailed(let status):
            "The shortcut could not be registered. It may already be used by macOS or another app. Carbon status: \(status)."
        }
    }
}

final class HotKeyManager {
    var onPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var eventHandlerStatus: OSStatus = OSStatus(eventNotHandledErr)
    private let hotKeyID = EventHotKeyID(signature: 0x434C4950, id: 1)

    init() {
        installEventHandler()
    }

    deinit {
        unregister()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    @discardableResult
    func register(_ hotKey: HotKey) -> Result<Void, HotKeyRegistrationError> {
        unregister()

        guard eventHandlerStatus == noErr else {
            return .failure(.eventHandlerUnavailable(eventHandlerStatus))
        }

        let status = RegisterEventHotKey(
            UInt32(hotKey.keyCode),
            hotKey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            NSLog("Failed to register global hotkey: \(status)")
            return .failure(.registrationFailed(status))
        }

        return .success(())
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        eventHandlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event,
                      let userData else {
                    return noErr
                }

                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                var pressedID = EventHotKeyID()

                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressedID
                )

                guard pressedID.signature == manager.hotKeyID.signature,
                      pressedID.id == manager.hotKeyID.id else {
                    return noErr
                }

                DispatchQueue.main.async {
                    manager.onPressed?()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )

        if eventHandlerStatus != noErr {
            NSLog("Failed to install hotkey event handler: \(eventHandlerStatus)")
        }
    }
}
