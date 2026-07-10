import AppKit
import ClipletCore

final class PreferencesWindowController: NSWindowController, NSTextFieldDelegate, NSWindowDelegate {
    private let settings: AppSettings
    private let history: ClipboardHistory
    private let hotKeyManager: HotKeyManager
    private let autoPasteController: AutoPasteController

    private let countField = NSTextField()
    private let stepper = NSStepper()
    private let shortcutButton: ShortcutRecorderButton
    private let pasteAfterSelectionButton = NSButton(checkboxWithTitle: "Paste into front app after selecting", target: nil, action: nil)
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")
    private let accessibilityButton = NSButton(title: "Grant Access...", target: nil, action: nil)

    init(
        settings: AppSettings,
        history: ClipboardHistory,
        hotKeyManager: HotKeyManager,
        autoPasteController: AutoPasteController
    ) {
        self.settings = settings
        self.history = history
        self.hotKeyManager = hotKeyManager
        self.autoPasteController = autoPasteController
        self.shortcutButton = ShortcutRecorderButton(hotKey: settings.hotKey)

        let window = PreferencesWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "cliplet Preferences"
        window.isReleasedWhenClosed = false

        super.init(window: window)

        window.delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        buildContent()
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func show() {
        guard let window else {
            return
        }

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateAccessibilityStatus()
    }

    private func buildContent() {
        guard let contentView = window?.contentView else {
            return
        }

        let titleLabel = NSTextField(labelWithString: "cliplet")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let historyLabel = NSTextField(labelWithString: "History items")
        historyLabel.translatesAutoresizingMaskIntoConstraints = false

        countField.integerValue = settings.historyLimit
        countField.formatter = integerFormatter
        countField.delegate = self
        countField.alignment = .right
        countField.translatesAutoresizingMaskIntoConstraints = false

        stepper.minValue = 1
        stepper.maxValue = 200
        stepper.increment = 1
        stepper.integerValue = settings.historyLimit
        stepper.target = self
        stepper.action = #selector(stepperChanged)
        stepper.translatesAutoresizingMaskIntoConstraints = false

        let shortcutLabel = NSTextField(labelWithString: "Global shortcut")
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false

        shortcutButton.onRecordingStarted = { [weak self] in
            self?.hotKeyManager.unregister()
        }
        shortcutButton.onRecordingCancelled = { [weak self] in
            guard let self else {
                return
            }

            self.restoreStoredHotKey()
        }
        shortcutButton.onShortcutChange = { [weak self] hotKey in
            self?.saveHotKeyIfAvailable(hotKey)
        }
        shortcutButton.translatesAutoresizingMaskIntoConstraints = false

        let selectionLabel = NSTextField(labelWithString: "Selection")
        selectionLabel.translatesAutoresizingMaskIntoConstraints = false

        pasteAfterSelectionButton.state = settings.pasteAfterSelection ? .on : .off
        pasteAfterSelectionButton.target = self
        pasteAfterSelectionButton.action = #selector(pasteAfterSelectionChanged)
        pasteAfterSelectionButton.translatesAutoresizingMaskIntoConstraints = false

        accessibilityStatusLabel.font = .systemFont(ofSize: 11)
        accessibilityStatusLabel.lineBreakMode = .byTruncatingTail
        accessibilityStatusLabel.translatesAutoresizingMaskIntoConstraints = false

        accessibilityButton.bezelStyle = .rounded
        accessibilityButton.target = self
        accessibilityButton.action = #selector(requestAccessibilityPermission)
        accessibilityButton.translatesAutoresizingMaskIntoConstraints = false

        let resetButton = NSButton(title: "Reset", target: self, action: #selector(resetDefaults))
        resetButton.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(titleLabel)
        contentView.addSubview(historyLabel)
        contentView.addSubview(countField)
        contentView.addSubview(stepper)
        contentView.addSubview(shortcutLabel)
        contentView.addSubview(shortcutButton)
        contentView.addSubview(selectionLabel)
        contentView.addSubview(pasteAfterSelectionButton)
        contentView.addSubview(accessibilityStatusLabel)
        contentView.addSubview(accessibilityButton)
        contentView.addSubview(resetButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),

            historyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 28),
            historyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            historyLabel.widthAnchor.constraint(equalToConstant: 140),

            countField.centerYAnchor.constraint(equalTo: historyLabel.centerYAnchor),
            countField.leadingAnchor.constraint(equalTo: historyLabel.trailingAnchor, constant: 12),
            countField.widthAnchor.constraint(equalToConstant: 68),

            stepper.centerYAnchor.constraint(equalTo: countField.centerYAnchor),
            stepper.leadingAnchor.constraint(equalTo: countField.trailingAnchor, constant: 8),

            shortcutLabel.topAnchor.constraint(equalTo: historyLabel.bottomAnchor, constant: 24),
            shortcutLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            shortcutLabel.widthAnchor.constraint(equalTo: historyLabel.widthAnchor),

            shortcutButton.centerYAnchor.constraint(equalTo: shortcutLabel.centerYAnchor),
            shortcutButton.leadingAnchor.constraint(equalTo: shortcutLabel.trailingAnchor, constant: 12),
            shortcutButton.widthAnchor.constraint(equalToConstant: 140),

            selectionLabel.topAnchor.constraint(equalTo: shortcutLabel.bottomAnchor, constant: 26),
            selectionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            selectionLabel.widthAnchor.constraint(equalTo: historyLabel.widthAnchor),

            pasteAfterSelectionButton.centerYAnchor.constraint(equalTo: selectionLabel.centerYAnchor),
            pasteAfterSelectionButton.leadingAnchor.constraint(equalTo: selectionLabel.trailingAnchor, constant: 12),
            pasteAfterSelectionButton.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),

            accessibilityStatusLabel.topAnchor.constraint(equalTo: pasteAfterSelectionButton.bottomAnchor, constant: 8),
            accessibilityStatusLabel.leadingAnchor.constraint(equalTo: pasteAfterSelectionButton.leadingAnchor),
            accessibilityStatusLabel.trailingAnchor.constraint(lessThanOrEqualTo: accessibilityButton.leadingAnchor, constant: -10),

            accessibilityButton.centerYAnchor.constraint(equalTo: accessibilityStatusLabel.centerYAnchor),
            accessibilityButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            resetButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            resetButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])

        updateAccessibilityStatus()
    }

    private var integerFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.minimum = 1
        formatter.maximum = 200
        formatter.allowsFloats = false
        return formatter
    }

    @objc private func stepperChanged() {
        countField.integerValue = stepper.integerValue
        saveHistoryLimit(stepper.integerValue)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let value = HistoryLimitInput.parse(countField.stringValue) else {
            countField.integerValue = settings.historyLimit
            stepper.integerValue = settings.historyLimit
            NSSound.beep()
            return
        }

        countField.integerValue = value
        stepper.integerValue = value
        saveHistoryLimit(value)
    }

    func windowWillClose(_ notification: Notification) {
        shortcutButton.cancelRecordingIfNeeded()
    }

    @objc private func applicationDidBecomeActive() {
        updateAccessibilityStatus()
    }

    @objc private func resetDefaults() {
        shortcutButton.cancelRecordingIfNeeded()

        let defaultLimit = 50
        let defaultHotKey = HotKey(keyCode: 9, modifiers: [.control, .option])
        let defaultPasteAfterSelection = true

        countField.integerValue = defaultLimit
        stepper.integerValue = defaultLimit
        pasteAfterSelectionButton.state = defaultPasteAfterSelection ? .on : .off
        history.updateLimit(defaultLimit)
        settings.historyLimit = defaultLimit
        settings.pasteAfterSelection = defaultPasteAfterSelection
        saveHotKeyIfAvailable(defaultHotKey)
        updateAccessibilityStatus()

        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        NotificationCenter.default.post(name: .clipboardHistoryDidChange, object: nil)
    }

    private func saveHistoryLimit(_ value: Int) {
        settings.historyLimit = value
        history.updateLimit(value)
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        NotificationCenter.default.post(name: .clipboardHistoryDidChange, object: nil)
    }

    private func saveHotKeyIfAvailable(_ hotKey: HotKey) {
        switch hotKeyManager.register(hotKey) {
        case .success:
            settings.hotKey = hotKey
            shortcutButton.hotKey = hotKey
            NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        case .failure(let error):
            NSSound.beep()
            shortcutButton.hotKey = settings.hotKey
            restoreStoredHotKey()
            showHotKeyError(error)
        }
    }

    private func restoreStoredHotKey() {
        if case .failure(let error) = hotKeyManager.register(settings.hotKey) {
            NSLog("Failed to restore global hotkey: \(error.localizedDescription)")
        }
    }

    private func showHotKeyError(_ error: HotKeyRegistrationError) {
        guard let window else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Shortcut unavailable"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    @objc private func pasteAfterSelectionChanged() {
        let isEnabled = pasteAfterSelectionButton.state == .on
        settings.pasteAfterSelection = isEnabled
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)

        if isEnabled && !autoPasteController.isAccessibilityTrusted {
            autoPasteController.requestAccessibilityPermissionPrompt()
            showAccessibilityPermissionNotice()
        }

        updateAccessibilityStatus()
    }

    @objc private func requestAccessibilityPermission() {
        autoPasteController.requestAccessibilityPermissionPrompt()
        autoPasteController.openAccessibilitySettings()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.updateAccessibilityStatus()
        }
    }

    private func updateAccessibilityStatus() {
        let isTrusted = autoPasteController.isAccessibilityTrusted
        accessibilityButton.isHidden = !settings.pasteAfterSelection || isTrusted

        if !settings.pasteAfterSelection {
            accessibilityStatusLabel.stringValue = "Automatic paste is off"
            accessibilityStatusLabel.textColor = .secondaryLabelColor
        } else if isTrusted {
            accessibilityStatusLabel.stringValue = "Accessibility access granted"
            accessibilityStatusLabel.textColor = .secondaryLabelColor
        } else {
            accessibilityStatusLabel.stringValue = "Accessibility access required"
            accessibilityStatusLabel.textColor = .systemOrange
        }
    }

    private func showAccessibilityPermissionNotice() {
        guard let window else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Accessibility permission needed"
        alert.informativeText = "cliplet needs Accessibility access to paste into the frontmost app after you select a history item. Without it, items are still copied to the clipboard."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else {
                return
            }

            self?.autoPasteController.openAccessibilitySettings()
        }
    }
}

private final class PreferencesWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.commandOnly else {
            return super.performKeyEquivalent(with: event)
        }

        switch event.keyCode {
        case 13:
            close()
            return true
        case 12:
            NSApp.terminate(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

private final class ShortcutRecorderButton: NSButton {
    var onShortcutChange: ((HotKey) -> Void)?
    var onRecordingStarted: (() -> Void)?
    var onRecordingCancelled: (() -> Void)?

    var hotKey: HotKey {
        didSet {
            if !isRecording {
                title = hotKey.displayString
            }
        }
    }

    private var isRecording = false
    private var keyDownMonitor: Any?

    init(hotKey: HotKey) {
        self.hotKey = hotKey
        super.init(frame: .zero)
        title = hotKey.displayString
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        guard handleKeyDown(event) else {
            super.keyDown(with: event)
            return
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleKeyDown(event) || super.performKeyEquivalent(with: event)
    }

    @objc private func beginRecording() {
        guard !isRecording else {
            return
        }

        isRecording = true
        title = "Press shortcut"
        window?.makeFirstResponder(self)
        onRecordingStarted?()
        installKeyDownMonitor()
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard isRecording else {
            return false
        }

        if event.keyCode == 53 {
            cancelRecording()
            return true
        }

        let modifiers = event.modifierFlags.hotKeyModifiers
        guard !modifiers.isEmpty else {
            NSSound.beep()
            return true
        }

        let recorded = HotKey(keyCode: UInt16(event.keyCode), modifiers: modifiers)
        hotKey = recorded
        stopRecording()
        onShortcutChange?(recorded)
        return true
    }

    private func cancelRecording() {
        stopRecording()
        onRecordingCancelled?()
    }

    func cancelRecordingIfNeeded() {
        guard isRecording else {
            return
        }

        cancelRecording()
    }

    private func stopRecording() {
        isRecording = false
        title = hotKey.displayString
        removeKeyDownMonitor()
        window?.makeFirstResponder(nil)
    }

    private func installKeyDownMonitor() {
        removeKeyDownMonitor()

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            return self.handleKeyDown(event) ? nil : event
        }
    }

    private func removeKeyDownMonitor() {
        guard let keyDownMonitor else {
            return
        }

        NSEvent.removeMonitor(keyDownMonitor)
        self.keyDownMonitor = nil
    }

    deinit {
        removeKeyDownMonitor()
    }
}

private extension NSEvent.ModifierFlags {
    var commandOnly: Bool {
        intersection([.command, .option, .control, .shift]) == .command
    }
}
