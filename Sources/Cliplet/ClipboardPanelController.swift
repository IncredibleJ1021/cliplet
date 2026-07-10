import AppKit
import ClipletCore

final class ClipboardPanelController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let history: ClipboardHistory
    private let settings: AppSettings
    private let autoPasteController: AutoPasteController
    private let selectionService: ClipboardSelectionService
    private let tableView = NSTableView()
    private let searchField = NSSearchField()
    private let emptyLabel = NSTextField(labelWithString: "No clips yet")

    private var query = ""
    private var sourceApplication: NSRunningApplication?
    private var displayedItems: [ClipboardItem] {
        let allItems = history.items
        guard !query.isEmpty else {
            return allItems
        }

        return allItems.filter { $0.searchableText.localizedCaseInsensitiveContains(query) }
    }

    init(
        history: ClipboardHistory,
        settings: AppSettings,
        autoPasteController: AutoPasteController,
        onPasteboardWrite: @escaping () -> Void = {}
    ) {
        self.history = history
        self.settings = settings
        self.autoPasteController = autoPasteController
        self.selectionService = ClipboardSelectionService(
            history: history,
            onPasteboardWrite: onPasteboardWrite
        )

        let window = ClipboardPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 580),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "cliplet"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.minSize = NSSize(width: 420, height: 420)
        window.collectionBehavior = [.moveToActiveSpace, .transient]

        super.init(window: window)

        window.onConfirm = { [weak self] in
            self?.copySelectedClip()
        }
        window.onCancel = { [weak self] in
            self?.close()
        }

        buildContent()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(historyDidChange),
            name: .clipboardHistoryDidChange,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func show(sourceApplication: NSRunningApplication?) {
        self.sourceApplication = sourceApplication
        reloadItems()
        positionWindow()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(tableView)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildContent() {
        guard let contentView = window?.contentView else {
            return
        }

        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor

        let backgroundView = NSVisualEffectView()
        backgroundView.material = .popover
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = "Search"
        searchField.delegate = self
        searchField.font = .systemFont(ofSize: 15)
        searchField.controlSize = .large
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 78
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(copySelectedClip)
        tableView.allowsEmptySelection = false
        tableView.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 15, weight: .medium)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(backgroundView)
        backgroundView.addSubview(searchField)
        backgroundView.addSubview(scrollView)
        backgroundView.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            searchField.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 26),
            searchField.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 20),
            searchField.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -10),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])
    }

    private func positionWindow() {
        guard let window else {
            return
        }

        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = window.frame.size
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        )

        window.setFrameOrigin(origin)
    }

    @objc private func historyDidChange() {
        reloadItems()
    }

    private func reloadItems() {
        tableView.reloadData()
        emptyLabel.isHidden = !displayedItems.isEmpty

        guard !displayedItems.isEmpty else {
            tableView.deselectAll(nil)
            return
        }

        let selectedRow = tableView.selectedRow
        let rowToSelect = displayedItems.indices.contains(selectedRow) ? selectedRow : 0
        tableView.selectRowIndexes(IndexSet(integer: rowToSelect), byExtendingSelection: false)
        tableView.scrollRowToVisible(rowToSelect)
    }

    @objc private func copySelectedClip() {
        let selectedRow = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        guard displayedItems.indices.contains(selectedRow) else {
            return
        }

        let item = displayedItems[selectedRow]
        switch selectionService.copy(item) {
        case .copied(let historyChanged):
            if historyChanged {
                NotificationCenter.default.post(name: .clipboardHistoryDidChange, object: nil)
            }
        case .itemUnavailable, .pasteboardWriteFailed:
            NSSound.beep()
            return
        }

        close()

        guard settings.pasteAfterSelection else {
            return
        }

        if !autoPasteController.paste(to: sourceApplication) {
            autoPasteController.requestAccessibilityPermissionPrompt()
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        displayedItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("ClipletCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? ClipletCellView ?? ClipletCellView()
        cell.identifier = identifier
        let item = displayedItems[row]
        cell.configure(with: item, imageData: history.imageData(for: item))
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ClipletRowView()
    }

    func controlTextDidChange(_ obj: Notification) {
        query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        reloadItems()
    }
}

private final class ClipboardPanelWindow: NSPanel {
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onConfirm?()
        case 53:
            onCancel?()
        default:
            super.keyDown(with: event)
        }
    }

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

private extension NSEvent.ModifierFlags {
    var commandOnly: Bool {
        intersection([.command, .option, .control, .shift]) == .command
    }
}

private final class ClipletRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard isSelected else {
            return
        }

        drawSelectedBackground()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        drawSelectedBackground()
    }

    private func drawSelectedBackground() {
        let selectionRect = bounds.insetBy(dx: 10, dy: 4)
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: selectionRect, xRadius: 10, yRadius: 10).fill()
    }
}

private final class ClipletCellView: NSTableCellView {
    private let thumbnailView = NSImageView()
    private let contentLabel = NSTextField(labelWithString: "")
    private let dateLabel = NSTextField(labelWithString: "")
    private let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
    private let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(with item: ClipboardItem, imageData: Data?) {
        switch item.kind {
        case .text:
            thumbnailView.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "Text clip")
            thumbnailView.contentTintColor = .controlAccentColor
            thumbnailView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            thumbnailView.layer?.borderWidth = 0
            contentLabel.stringValue = (item.text ?? "").replacingOccurrences(of: "\n", with: " ")
            dateLabel.stringValue = formatter.localizedString(for: item.createdAt, relativeTo: Date())
        case .image:
            thumbnailView.image = imageData.flatMap(NSImage.init(data:)) ??
                NSImage(systemSymbolName: "photo", accessibilityDescription: "Image clip")
            thumbnailView.contentTintColor = nil
            thumbnailView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.06).cgColor
            thumbnailView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
            thumbnailView.layer?.borderWidth = 1
            contentLabel.stringValue = "Image"

            let metadata = [
                item.imageByteCount.map { byteFormatter.string(fromByteCount: Int64($0)) },
                formatter.localizedString(for: item.createdAt, relativeTo: Date())
            ].compactMap { $0 }
            dateLabel.stringValue = metadata.joined(separator: " • ")
        }
    }

    private func setup() {
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        thumbnailView.layer?.cornerRadius = 10
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false

        contentLabel.font = .systemFont(ofSize: 14, weight: .medium)
        contentLabel.lineBreakMode = .byTruncatingTail
        contentLabel.maximumNumberOfLines = 2
        contentLabel.textColor = .labelColor
        contentLabel.translatesAutoresizingMaskIntoConstraints = false

        dateLabel.font = .systemFont(ofSize: 11)
        dateLabel.textColor = .secondaryLabelColor
        dateLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(thumbnailView)
        addSubview(contentLabel)
        addSubview(dateLabel)

        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            thumbnailView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 48),
            thumbnailView.heightAnchor.constraint(equalToConstant: 48),

            contentLabel.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 14),
            contentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            contentLabel.topAnchor.constraint(equalTo: topAnchor, constant: 13),

            dateLabel.leadingAnchor.constraint(equalTo: contentLabel.leadingAnchor),
            dateLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentLabel.trailingAnchor),
            dateLabel.topAnchor.constraint(equalTo: contentLabel.bottomAnchor, constant: 6),
            dateLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12)
        ])
    }
}
