import AppKit
import ClipCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private lazy var history = ClipboardHistory(limit: settings.historyLimit)
    private lazy var monitor = ClipboardMonitor(history: history)
    private let hotKeyManager = HotKeyManager()

    private var statusItem: NSStatusItem?
    private var clipboardPanelController: ClipboardPanelController?
    private var preferencesController: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()

        hotKeyManager.onPressed = { [weak self] in
            self?.toggleClipboardPanel()
        }
        hotKeyManager.register(settings.hotKey)

        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        hotKeyManager.unregister()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Clip")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Clipboard", action: #selector(openClipboardPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Clip", action: #selector(quit), keyEquivalent: "q"))
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
            clipboardPanelController = ClipboardPanelController(history: history)
        }

        clipboardPanelController?.show()
    }

    @objc private func openPreferences() {
        if preferencesController == nil {
            preferencesController = PreferencesWindowController(
                settings: settings,
                history: history,
                hotKeyManager: hotKeyManager
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
}
