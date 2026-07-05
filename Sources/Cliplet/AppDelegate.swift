import AppKit
import ClipletCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private lazy var history = ClipboardHistory(limit: settings.historyLimit)
    private lazy var monitor = ClipboardMonitor(history: history)
    private let hotKeyManager = HotKeyManager()
    private let autoPasteController = AutoPasteController()

    private var statusItem: NSStatusItem?
    private var clipboardPanelController: ClipboardPanelController?
    private var preferencesController: PreferencesWindowController?
    private var lastTargetApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        observeActiveApplicationChanges()

        hotKeyManager.onPressed = { [weak self] in
            self?.toggleClipboardPanel()
        }
        registerConfiguredHotKey()

        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        hotKeyManager.unregister()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "cliplet")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Clipboard", action: #selector(openClipboardPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit cliplet", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }

        item.menu = menu
        statusItem = item
    }

    @objc private func openClipboardPanel() {
        showClipboardPanel()
    }

    private func toggleClipboardPanel() {
        if clipboardPanelController?.window?.isVisible == true {
            clipboardPanelController?.close()
        } else {
            showClipboardPanel()
        }
    }

    private func showClipboardPanel() {
        if clipboardPanelController == nil {
            clipboardPanelController = ClipboardPanelController(
                history: history,
                settings: settings,
                autoPasteController: autoPasteController,
                onPasteboardWrite: { [weak monitor] in
                    monitor?.syncChangeCount()
                }
            )
        }

        clipboardPanelController?.show(sourceApplication: currentTargetApplication())
    }

    private func registerConfiguredHotKey() {
        if case .failure(let error) = hotKeyManager.register(settings.hotKey) {
            NSLog("Failed to register configured hotkey: \(error.localizedDescription)")
        }
    }

    @objc private func openPreferences() {
        if preferencesController == nil {
            preferencesController = PreferencesWindowController(
                settings: settings,
                history: history,
                hotKeyManager: hotKeyManager,
                autoPasteController: autoPasteController
            )
        }

        preferencesController?.show()
    }

    @objc private func clearHistory() {
        history.clear()
        NotificationCenter.default.post(name: .clipboardHistoryDidChange, object: nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func observeActiveApplicationChanges() {
        updateLastTargetApplication(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationDidChange),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func activeApplicationDidChange(_ notification: Notification) {
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        updateLastTargetApplication(application)
    }

    private func updateLastTargetApplication(_ application: NSRunningApplication?) {
        guard let application, !isCliplet(application) else {
            return
        }

        lastTargetApplication = application
    }

    private func currentTargetApplication() -> NSRunningApplication? {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
            return lastTargetApplication
        }

        return isCliplet(frontmostApplication) ? lastTargetApplication : frontmostApplication
    }

    private func isCliplet(_ application: NSRunningApplication) -> Bool {
        application.bundleIdentifier == Bundle.main.bundleIdentifier ||
            application.processIdentifier == NSRunningApplication.current.processIdentifier
    }
}
