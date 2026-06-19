import AppKit
import ClipletCore

final class PreferencesWindowController: NSWindowController, NSTextFieldDelegate, NSWindowDelegate {
    private let settings: AppSettings
    private let history: ClipboardHistory
    private let hotKeyManager: HotKeyManager

    private let countField = NSTextField()
    private let stepper = NSStepper()
    private let shortcutButton: ShortcutRecorderButton

    init(settings: AppSettings, history: ClipboardHistory, hotKeyManager: HotKeyManager) {
        self.settings = settings
        self.history = history
        self.hotKeyManager = hotKeyManager
        self.shortcutButton = ShortcutRecorderButton(hotKey: settings.hotKey)

        let window = PreferencesWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "cliplet Preferences"
        window.isReleasedWhenClosed = false

        super.init(window: window)

        window.delegate = self
        buildContent()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else {
            return
        }

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

            self.hotKeyManager.register(self.settings.hotKey)
        }
        shortcutButton.onShortcutChange = { [weak self] hotKey in
            self?.settings.hotKey = hotKey
            self?.hotKeyManager.register(hotKey)
            NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        }
        shortcutButton.translatesAutoresizingMaskIntoConstraints = false

        let resetButton = NSButton(title: "Reset", target: self, action: #selector(resetDefaults))
        resetButton.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(titleLabel)
        contentView.addSubview(historyLabel)
        contentView.addSubview(countField)
        contentView.addSubview(stepper)
        contentView.addSubview(shortcutLabel)
        contentView.addSubview(shortcutButton)
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

            resetButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            resetButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
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
        let value = min(max(countField.integerValue, 1), 200)
        countField.integerValue = value
        stepper.integerValue = value
        saveHistoryLimit(value)
    }

    func windowWillClose(_ notification: Notification) {
        shortcutButton.cancelRecordingIfNeeded()
    }

    @objc private func resetDefaults() {
        shortcutButton.cancelRecordingIfNeeded()

        let defaultLimit = 50
        let defaultHotKey = HotKey(keyCode: 9, modifiers: [.control, .option])

        countField.integerValue = defaultLimit
        stepper.integerValue = defaultLimit
        shortcutButton.hotKey = defaultHotKey

        settings.historyLimit = defaultLimit
        settings.hotKey = defaultHotKey
        history.updateLimit(defaultLimit)
        hotKeyManager.register(defaultHotKey)

        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        NotificationCenter.default.post(name: .clipboardHistoryDidChange, object: nil)
    }

    private func saveHistoryLimit(_ value: Int) {
        settings.historyLimit = value
        history.updateLimit(value)
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
        NotificationCenter.default.post(name: .clipboardHistoryDidChange, object: nil)
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
