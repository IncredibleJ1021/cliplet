import AppKit
import ClipletCore

final class ClipboardPanelController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let history: ClipboardHistory
    private let tableView = NSTableView()
    private let searchField = NSSearchField()
    private let emptyLabel = NSTextField(labelWithString: "No clips yet")

    private var query = ""
    private var displayedItems: [ClipboardItem] {
        let allItems = history.items
        guard !query.isEmpty else {
            return allItems
        }

        return allItems.filter { $0.searchableText.localizedCaseInsensitiveContains(query) }
    }

    init(history: ClipboardHistory) {
        self.history = history

        let window = ClipboardPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "cliplet"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.minSize = NSSize(width: 360, height: 360)
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

    func show() {
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
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        searchField.placeholderString = "Search"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 84
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

        contentView.addSubview(searchField)
        contentView.addSubview(scrollView)
        contentView.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

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

        if !displayedItems.isEmpty && tableView.selectedRow < 0 {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    @objc private func copySelectedClip() {
        let selectedRow = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        guard displayedItems.indices.contains(selectedRow) else {
            return
        }

        let item = displayedItems[selectedRow]
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .text:
            guard let text = item.text else {
                return
            }

            pasteboard.setString(text, forType: .string)
            history.add(text)
        case .image:
            guard let imageData = item.imageData else {
                return
            }

            let pasteboardType = NSPasteboard.PasteboardType(rawValue: item.imagePasteboardType ?? NSPasteboard.PasteboardType.png.rawValue)
            pasteboard.setData(imageData, forType: pasteboardType)
            history.addImageData(imageData, pasteboardType: pasteboardType.rawValue)
        }

        NotificationCenter.default.post(name: .clipboardHistoryDidChange, object: nil)
        close()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        displayedItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("ClipletCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? ClipletCellView ?? ClipletCellView()
        cell.identifier = identifier
        cell.configure(with: displayedItems[row])
        return cell
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

    func configure(with item: ClipboardItem) {
        switch item.kind {
        case .text:
            thumbnailView.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "Text clip")
            contentLabel.stringValue = (item.text ?? "").replacingOccurrences(of: "\n", with: " ")
            dateLabel.stringValue = formatter.localizedString(for: item.createdAt, relativeTo: Date())
        case .image:
            thumbnailView.image = item.imageData.flatMap(NSImage.init(data:))
            contentLabel.stringValue = "Image"

            let metadata = [
                item.imageData.map { byteFormatter.string(fromByteCount: Int64($0.count)) },
                formatter.localizedString(for: item.createdAt, relativeTo: Date())
            ].compactMap { $0 }
            dateLabel.stringValue = metadata.joined(separator: " • ")
        }
    }

    private func setup() {
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        thumbnailView.layer?.cornerRadius = 6
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false

        contentLabel.font = .systemFont(ofSize: 14)
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
            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            thumbnailView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 54),
            thumbnailView.heightAnchor.constraint(equalToConstant: 54),

            contentLabel.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 12),
            contentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            contentLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),

            dateLabel.leadingAnchor.constraint(equalTo: contentLabel.leadingAnchor),
            dateLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentLabel.trailingAnchor),
            dateLabel.topAnchor.constraint(equalTo: contentLabel.bottomAnchor, constant: 6),
            dateLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12)
        ])
    }
}
