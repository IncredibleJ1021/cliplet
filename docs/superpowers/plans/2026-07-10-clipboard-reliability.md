# Clipboard Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make history selection, image deduplication, automatic paste, and destructive settings safe and testable for cliplet v0.4.1.

**Architecture:** Keep persistence rules in `ClipletCore`; add focused AppKit-side services for writing selected items and coordinating automatic paste. UI controllers become thin consumers of typed results, while injected closures make system interactions deterministic in tests.

**Tech Stack:** Swift 5.9 language mode, Swift Package Manager, Foundation, AppKit, ApplicationServices, XCTest.

## Global Constraints

- Deployment target remains macOS 13.0.
- Do not add third-party dependencies or migrate history storage in this release.
- `ClipletCore` remains Foundation-only.
- Automatic paste must never post a keyboard event unless the intended target is confirmed frontmost.
- Existing text/image migration behavior remains backward compatible.

## File Structure

- Modify `Sources/ClipletCore/ClipboardHistory.swift`: add ID-based promotion and exact duplicate lookup.
- Modify `Sources/ClipletCore/ClipboardImageStore.swift`: accept a precomputed fingerprint to avoid hashing new data twice.
- Modify `Tests/ClipletCoreTests/ClipboardHistoryTests.swift`: cover promotion, file reuse, and collision-safe deduplication.
- Create `Sources/Cliplet/ClipboardSelectionService.swift`: own pasteboard writes and selection-to-history promotion.
- Modify `Sources/Cliplet/ClipboardPanelController.swift`: consume selection and auto-paste results.
- Modify `Sources/Cliplet/AutoPasteController.swift`: replace fixed-delay fire-and-forget behavior with a typed asynchronous result.
- Create `Sources/Cliplet/HistoryLimitInput.swift`: parse the history-limit field without destructive coercion.
- Modify `Sources/Cliplet/PreferencesWindowController.swift`: apply only valid history limits.
- Modify `Sources/Cliplet/AppDelegate.swift`: confirm before clearing history.
- Modify `Package.swift`: add an AppKit test target.
- Create `Tests/ClipletTests/ClipboardSelectionServiceTests.swift`: verify pasteboard failure cannot update history.
- Create `Tests/ClipletTests/AutoPasteControllerTests.swift`: verify activation and event-posting safety.
- Create `Tests/ClipletTests/HistoryLimitInputTests.swift`: verify invalid fields cannot prune history.

---

### Task 1: Promote Existing History Items Without Rewriting Images

**Files:**
- Modify: `Tests/ClipletCoreTests/ClipboardHistoryTests.swift`
- Modify: `Sources/ClipletCore/ClipboardHistory.swift`
- Modify: `Sources/ClipletCore/ClipboardImageStore.swift`

**Interfaces:**
- Produces: `ClipboardHistory.promote(_ id: UUID, createdAt: Date = Date()) -> Bool`
- Produces: `ClipboardImageStore.store(_:pasteboardType:id:fingerprint:) throws -> ClipboardImage`
- Consumes: existing `ClipboardHistory.imageData(for:)` and `Data.clipletFingerprint`

- [ ] **Step 1: Add failing promotion and duplicate-file tests**

Add these tests to `ClipboardHistoryTests`:

```swift
func testPromotesExistingTextItemWithoutChangingID() {
    let defaults = makeDefaults()
    let history = makeHistory(defaults: defaults, limit: 5)
    let promotedAt = Date(timeIntervalSince1970: 123)

    history.add("first")
    history.add("second")
    let firstID = history.items.last!.id

    XCTAssertTrue(history.promote(firstID, createdAt: promotedAt))
    XCTAssertEqual(history.items.first?.id, firstID)
    XCTAssertEqual(history.items.first?.text, "first")
    XCTAssertEqual(history.items.first?.createdAt, promotedAt)
}

func testPromotesExistingImageWithoutCreatingAnotherFile() throws {
    let defaults = makeDefaults()
    let imageStore = makeImageStore()
    let history = ClipboardHistory(defaults: defaults, storageKey: "items", limit: 5, imageStore: imageStore)
    let data = Data([0, 1, 2, 3])

    history.addImageData(data, pasteboardType: "public.png")
    let original = history.items[0]
    let originalKey = original.imageStorageKey

    XCTAssertTrue(history.promote(original.id, createdAt: Date(timeIntervalSince1970: 456)))
    XCTAssertEqual(history.items.first?.imageStorageKey, originalKey)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: imageStore.directoryURL.path).count, 1)
}

func testAddingDuplicateImageReusesExistingFile() throws {
    let defaults = makeDefaults()
    let imageStore = makeImageStore()
    let history = ClipboardHistory(defaults: defaults, storageKey: "items", limit: 5, imageStore: imageStore)
    let data = Data([0, 1, 2, 3])

    history.addImageData(data, pasteboardType: "public.png")
    let originalKey = history.items.first?.imageStorageKey
    history.addImageData(data, pasteboardType: "public.png")

    XCTAssertEqual(history.items.count, 1)
    XCTAssertEqual(history.items.first?.imageStorageKey, originalKey)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: imageStore.directoryURL.path).count, 1)
}
```

- [ ] **Step 2: Run the focused tests and confirm the new API is missing**

Run:

```bash
swift test --filter ClipboardHistoryTests
```

Expected: compilation fails because `ClipboardHistory` has no `promote` method.

- [ ] **Step 3: Implement ID-based promotion**

Add to `ClipboardHistory`:

```swift
@discardableResult
public func promote(_ id: UUID, createdAt: Date = Date()) -> Bool {
    guard let index = items.firstIndex(where: { $0.id == id }) else {
        return false
    }

    let existing = items.remove(at: index)
    let promoted: ClipboardItem
    switch existing.payload {
    case .text(let text):
        promoted = ClipboardItem(id: existing.id, content: text, createdAt: createdAt)
    case .image(let image):
        promoted = ClipboardItem(id: existing.id, image: image, createdAt: createdAt)
    }

    items.insert(promoted, at: 0)
    persistAndPruneImages()
    return true
}
```

Replace the duplicate branch in `add(_:)` with:

```swift
if let existing = items.first(where: { $0.text == content }) {
    return promote(existing.id, createdAt: createdAt)
}
```

- [ ] **Step 4: Deduplicate images before writing**

Change the image-store signature to:

```swift
public func store(
    _ data: Data,
    pasteboardType: String,
    id: UUID = UUID(),
    fingerprint: String? = nil
) throws -> ClipboardImage {
```

Construct the returned `ClipboardImage` with:

```swift
return ClipboardImage(
    storage: .file(key),
    pasteboardType: pasteboardType,
    byteCount: data.count,
    fingerprint: fingerprint ?? data.clipletFingerprint
)
```

Replace the body of `ClipboardHistory.addImageData` after its empty-data guard with:

```swift
let fingerprint = imageData.clipletFingerprint
if let existing = items.first(where: {
    $0.imagePasteboardType == pasteboardType &&
        $0.imageByteCount == imageData.count &&
        $0.imageFingerprint == fingerprint
}), imageData(for: existing) == imageData {
    return promote(existing.id, createdAt: createdAt)
}

let id = UUID()
let image: ClipboardImage
do {
    image = try imageStore.store(
        imageData,
        pasteboardType: pasteboardType,
        id: id,
        fingerprint: fingerprint
    )
} catch {
    return false
}

items.insert(ClipboardItem(id: id, image: image, createdAt: createdAt), at: 0)
trimToLimit()
persistAndPruneImages()
return true
```

- [ ] **Step 5: Add a collision-candidate regression test**

Add a test that stores bytes different from the next image but metadata matching its size and fingerprint:

```swift
func testFingerprintCandidateRequiresExactByteEquality() throws {
    let defaults = makeDefaults()
    let imageStore = makeImageStore()
    let newData = Data([9, 8, 7, 6])
    let storedData = Data([1, 2, 3, 4])
    let key = "collision.png"
    try FileManager.default.createDirectory(at: imageStore.directoryURL, withIntermediateDirectories: true)
    try storedData.write(to: imageStore.directoryURL.appendingPathComponent(key))

    let existing = ClipboardItem(
        image: ClipboardImage(
            storage: .file(key),
            pasteboardType: "public.png",
            byteCount: newData.count,
            fingerprint: newData.clipletFingerprint
        )
    )
    defaults.set(try JSONEncoder().encode([existing]), forKey: "items")
    let history = ClipboardHistory(defaults: defaults, storageKey: "items", limit: 5, imageStore: imageStore)

    XCTAssertTrue(history.addImageData(newData, pasteboardType: "public.png"))
    XCTAssertEqual(history.items.count, 2)
    XCTAssertEqual(history.items.first.flatMap { history.imageData(for: $0) }, newData)
}
```

- [ ] **Step 6: Run Core tests**

Run:

```bash
swift test --filter ClipboardHistoryTests
```

Expected: all `ClipboardHistoryTests` pass.

- [ ] **Step 7: Commit the Core change**

```bash
git add Sources/ClipletCore/ClipboardHistory.swift Sources/ClipletCore/ClipboardImageStore.swift Tests/ClipletCoreTests/ClipboardHistoryTests.swift
git commit -m "Optimize clipboard history promotion"
```

---

### Task 2: Make Selection Writes Explicit and Testable

**Files:**
- Modify: `Package.swift`
- Create: `Sources/Cliplet/ClipboardSelectionService.swift`
- Create: `Tests/ClipletTests/ClipboardSelectionServiceTests.swift`
- Modify: `Sources/Cliplet/ClipboardPanelController.swift`

**Interfaces:**
- Consumes: `ClipboardHistory.promote(_:createdAt:) -> Bool`
- Produces: `ClipboardWriting.writeText(_:) -> Bool`
- Produces: `ClipboardWriting.writeImage(_:pasteboardType:) -> Bool`
- Produces: `ClipboardSelectionService.copy(_:) -> ClipboardSelectionResult`

- [ ] **Step 1: Add the AppKit test target**

Add to `Package.swift` after `ClipletCoreTests`:

```swift
.testTarget(
    name: "ClipletTests",
    dependencies: ["Cliplet", "ClipletCore"]
)
```

- [ ] **Step 2: Write failing selection-service tests**

Create `Tests/ClipletTests/ClipboardSelectionServiceTests.swift`:

```swift
import AppKit
import XCTest
@testable import Cliplet
@testable import ClipletCore

final class ClipboardSelectionServiceTests: XCTestCase {
    func testWriteFailureDoesNotPromoteOrSyncHistory() {
        let history = makeHistory()
        history.add("first")
        history.add("second")
        let first = history.items.last!
        let writer = WriterStub(textResult: false, imageResult: false)
        var syncCount = 0
        let service = ClipboardSelectionService(
            history: history,
            writer: writer,
            onPasteboardWrite: { syncCount += 1 }
        )

        XCTAssertEqual(service.copy(first), .pasteboardWriteFailed)
        XCTAssertEqual(history.items.map(\.text), ["second", "first"])
        XCTAssertEqual(syncCount, 0)
    }

    func testSuccessfulTextWritePromotesAndSyncsOnce() {
        let history = makeHistory()
        history.add("first")
        history.add("second")
        let first = history.items.last!
        let writer = WriterStub(textResult: true, imageResult: true)
        var syncCount = 0
        let service = ClipboardSelectionService(
            history: history,
            writer: writer,
            onPasteboardWrite: { syncCount += 1 }
        )

        XCTAssertEqual(service.copy(first), .copied(historyChanged: true))
        XCTAssertEqual(writer.writtenText, "first")
        XCTAssertEqual(history.items.first?.id, first.id)
        XCTAssertEqual(syncCount, 1)
    }

    func testImageWriteFailureDoesNotPromoteOrSyncHistory() {
        let history = makeHistory()
        history.addImageData(Data([0, 1, 2, 3]), pasteboardType: "public.png")
        let image = history.items.first!
        history.add("newer text")
        let writer = WriterStub(textResult: true, imageResult: false)
        var syncCount = 0
        let service = ClipboardSelectionService(
            history: history,
            writer: writer,
            onPasteboardWrite: { syncCount += 1 }
        )

        XCTAssertEqual(service.copy(image), .pasteboardWriteFailed)
        XCTAssertEqual(history.items.last?.id, image.id)
        XCTAssertEqual(syncCount, 0)
    }

    private func makeHistory() -> ClipboardHistory {
        let suite = "ClipletSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(suite, isDirectory: true)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        return ClipboardHistory(
            defaults: defaults,
            storageKey: "items",
            limit: 5,
            imageStore: ClipboardImageStore(directoryURL: directory)
        )
    }
}

private final class WriterStub: ClipboardWriting {
    let textResult: Bool
    let imageResult: Bool
    var writtenText: String?

    init(textResult: Bool, imageResult: Bool) {
        self.textResult = textResult
        self.imageResult = imageResult
    }

    func writeText(_ text: String) -> Bool {
        writtenText = text
        return textResult
    }

    func writeImage(_ data: Data, pasteboardType: String) -> Bool {
        imageResult
    }
}
```

- [ ] **Step 3: Run the new test target and verify missing types**

Run:

```bash
swift test --filter ClipboardSelectionServiceTests
```

Expected: compilation fails because `ClipboardWriting` and `ClipboardSelectionService` do not exist.

- [ ] **Step 4: Implement the selection service**

Create `Sources/Cliplet/ClipboardSelectionService.swift`:

```swift
import AppKit
import ClipletCore

protocol ClipboardWriting {
    func writeText(_ text: String) -> Bool
    func writeImage(_ data: Data, pasteboardType: String) -> Bool
}

final class SystemClipboardWriter: ClipboardWriting {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func writeText(_ text: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    func writeImage(_ data: Data, pasteboardType: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setData(data, forType: NSPasteboard.PasteboardType(pasteboardType))
    }
}

enum ClipboardSelectionResult: Equatable {
    case copied(historyChanged: Bool)
    case itemUnavailable
    case pasteboardWriteFailed
}

final class ClipboardSelectionService {
    private let history: ClipboardHistory
    private let writer: ClipboardWriting
    private let onPasteboardWrite: () -> Void

    init(
        history: ClipboardHistory,
        writer: ClipboardWriting = SystemClipboardWriter(),
        onPasteboardWrite: @escaping () -> Void = {}
    ) {
        self.history = history
        self.writer = writer
        self.onPasteboardWrite = onPasteboardWrite
    }

    func copy(_ item: ClipboardItem) -> ClipboardSelectionResult {
        let didWrite: Bool
        switch item.payload {
        case .text(let text):
            didWrite = writer.writeText(text)
        case .image:
            guard let data = history.imageData(for: item),
                  let pasteboardType = item.imagePasteboardType else {
                return .itemUnavailable
            }
            didWrite = writer.writeImage(data, pasteboardType: pasteboardType)
        }

        guard didWrite else {
            return .pasteboardWriteFailed
        }

        let historyChanged = history.promote(item.id)
        onPasteboardWrite()
        return .copied(historyChanged: historyChanged)
    }
}
```

- [ ] **Step 5: Replace direct pasteboard access in the panel**

Add a `selectionService` property and initialize it in `ClipboardPanelController.init`:

```swift
private let selectionService: ClipboardSelectionService
```

```swift
self.selectionService = ClipboardSelectionService(
    history: history,
    onPasteboardWrite: onPasteboardWrite
)
```

Replace the pasteboard switch in `copySelectedClip()` with:

```swift
switch selectionService.copy(item) {
case .copied(let historyChanged):
    if historyChanged {
        NotificationCenter.default.post(name: .clipboardHistoryDidChange, object: nil)
    }
case .itemUnavailable, .pasteboardWriteFailed:
    NSSound.beep()
    return
}
```

Remove the no-longer-used `onPasteboardWrite` stored property from the panel controller; keep the initializer parameter because it is passed into the service.

- [ ] **Step 6: Run selection and Core tests**

Run:

```bash
swift test --filter ClipboardSelectionServiceTests
swift test --filter ClipboardHistoryTests
```

Expected: both filtered suites pass.

- [ ] **Step 7: Commit the selection boundary**

```bash
git add Package.swift Sources/Cliplet/ClipboardSelectionService.swift Sources/Cliplet/ClipboardPanelController.swift Tests/ClipletTests/ClipboardSelectionServiceTests.swift
git commit -m "Make clipboard selection writes reliable"
```

---

### Task 3: Confirm the Target Before Automatic Paste

**Files:**
- Create: `Tests/ClipletTests/AutoPasteControllerTests.swift`
- Modify: `Sources/Cliplet/AutoPasteController.swift`
- Modify: `Sources/Cliplet/ClipboardPanelController.swift`

**Interfaces:**
- Produces: `AutoPasteResult`
- Produces: `AutoPasteEnvironment`
- Produces: `AutoPasteController.paste(to:completion:)`
- Consumes: `NSRunningApplication.processIdentifier`

- [ ] **Step 1: Write failing automatic-paste tests**

Create `Tests/ClipletTests/AutoPasteControllerTests.swift`:

```swift
import AppKit
import XCTest
@testable import Cliplet

final class AutoPasteControllerTests: XCTestCase {
    func testDeniedPermissionDoesNotActivateOrPost() {
        var activationCount = 0
        var postCount = 0
        let controller = makeController(
            isTrusted: false,
            activate: { _ in activationCount += 1; return true },
            frontmostPID: { NSRunningApplication.current.processIdentifier },
            postCommandV: { postCount += 1; return true }
        )
        var result: AutoPasteResult?

        controller.paste(to: .current) { result = $0 }

        XCTAssertEqual(result, .accessibilityDenied)
        XCTAssertEqual(activationCount, 0)
        XCTAssertEqual(postCount, 0)
    }

    func testMissingTargetDoesNotPost() {
        var postCount = 0
        let controller = makeController(postCommandV: { postCount += 1; return true })
        var result: AutoPasteResult?

        controller.paste(to: nil) { result = $0 }

        XCTAssertEqual(result, .targetUnavailable)
        XCTAssertEqual(postCount, 0)
    }

    func testActivationFailureDoesNotPost() {
        var postCount = 0
        let controller = makeController(
            activate: { _ in false },
            postCommandV: { postCount += 1; return true }
        )
        var result: AutoPasteResult?

        controller.paste(to: .current) { result = $0 }

        XCTAssertEqual(result, .activationFailed)
        XCTAssertEqual(postCount, 0)
    }

    func testUnavailableTargetDoesNotActivateOrPost() {
        var activationCount = 0
        var postCount = 0
        let controller = makeController(
            isApplicationAvailable: { _ in false },
            activate: { _ in activationCount += 1; return true },
            postCommandV: { postCount += 1; return true }
        )
        var result: AutoPasteResult?

        controller.paste(to: .current) { result = $0 }

        XCTAssertEqual(result, .targetUnavailable)
        XCTAssertEqual(activationCount, 0)
        XCTAssertEqual(postCount, 0)
    }

    func testPostsOnceAfterTargetBecomesFrontmost() {
        let target = NSRunningApplication.current
        var frontmostChecks = 0
        var postCount = 0
        let controller = makeController(
            frontmostPID: {
                frontmostChecks += 1
                return frontmostChecks >= 2 ? target.processIdentifier : nil
            },
            postCommandV: { postCount += 1; return true }
        )
        var result: AutoPasteResult?

        controller.paste(to: target) { result = $0 }

        XCTAssertEqual(result, .pasted)
        XCTAssertEqual(postCount, 1)
    }

    func testTimesOutWithoutPosting() {
        var postCount = 0
        let controller = makeController(
            frontmostPID: { nil },
            postCommandV: { postCount += 1; return true },
            activationTimeout: 0.04,
            pollInterval: 0.02
        )
        var result: AutoPasteResult?

        controller.paste(to: .current) { result = $0 }

        XCTAssertEqual(result, .activationTimedOut)
        XCTAssertEqual(postCount, 0)
    }

    func testEventCreationFailureIsReported() {
        let controller = makeController(postCommandV: { false })
        var result: AutoPasteResult?

        controller.paste(to: .current) { result = $0 }

        XCTAssertEqual(result, .eventPostingFailed)
    }

    private func makeController(
        isTrusted: Bool = true,
        isApplicationAvailable: @escaping (NSRunningApplication) -> Bool = { _ in true },
        activate: @escaping (NSRunningApplication) -> Bool = { _ in true },
        frontmostPID: @escaping () -> pid_t? = { NSRunningApplication.current.processIdentifier },
        postCommandV: @escaping () -> Bool = { true },
        activationTimeout: TimeInterval = 0.5,
        pollInterval: TimeInterval = 0.02
    ) -> AutoPasteController {
        let environment = AutoPasteEnvironment(
            isTrusted: { isTrusted },
            isApplicationAvailable: isApplicationAvailable,
            activate: activate,
            frontmostPID: frontmostPID,
            postCommandV: postCommandV,
            schedule: { _, action in action() }
        )
        return AutoPasteController(
            environment: environment,
            activationTimeout: activationTimeout,
            pollInterval: pollInterval
        )
    }
}
```

- [ ] **Step 2: Run the test and confirm the typed API is missing**

Run:

```bash
swift test --filter AutoPasteControllerTests
```

Expected: compilation fails because `AutoPasteResult` and `AutoPasteEnvironment` do not exist.

- [ ] **Step 3: Replace the fixed-delay implementation**

Replace `AutoPasteController.swift` with:

```swift
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
```

- [ ] **Step 4: Consume the typed result in the panel**

Replace the synchronous paste call in `ClipboardPanelController.copySelectedClip()` with:

```swift
autoPasteController.paste(to: sourceApplication) { [weak self] result in
    guard let self else {
        return
    }
    switch result {
    case .pasted:
        break
    case .accessibilityDenied:
        self.autoPasteController.requestAccessibilityPermissionPrompt()
    case .targetUnavailable, .activationFailed, .activationTimedOut, .eventPostingFailed:
        NSLog("Automatic paste fell back to copy-only: \(String(describing: result))")
    }
}
```

- [ ] **Step 5: Run automatic-paste tests**

Run:

```bash
swift test --filter AutoPasteControllerTests
```

Expected: all automatic-paste tests pass and no test posts a real keyboard event.

- [ ] **Step 6: Commit the automatic-paste change**

```bash
git add Sources/Cliplet/AutoPasteController.swift Sources/Cliplet/ClipboardPanelController.swift Tests/ClipletTests/AutoPasteControllerTests.swift
git commit -m "Verify target before automatic paste"
```

---

### Task 4: Protect History Limit and Clear History

**Files:**
- Create: `Sources/Cliplet/HistoryLimitInput.swift`
- Create: `Tests/ClipletTests/HistoryLimitInputTests.swift`
- Modify: `Sources/Cliplet/PreferencesWindowController.swift`
- Modify: `Sources/Cliplet/AppDelegate.swift`

**Interfaces:**
- Produces: `HistoryLimitInput.parse(_:) -> Int?`
- Consumes: `ClipboardHistory.updateLimit(_:)`

- [ ] **Step 1: Write failing limit-parser tests**

Create `Tests/ClipletTests/HistoryLimitInputTests.swift`:

```swift
import XCTest
@testable import Cliplet

final class HistoryLimitInputTests: XCTestCase {
    func testParsesValidTrimmedInteger() {
        XCTAssertEqual(HistoryLimitInput.parse(" 50 "), 50)
    }

    func testRejectsBlankAndNonNumericValues() {
        XCTAssertNil(HistoryLimitInput.parse(""))
        XCTAssertNil(HistoryLimitInput.parse("   "))
        XCTAssertNil(HistoryLimitInput.parse("ten"))
    }

    func testRejectsValuesOutsideSupportedRange() {
        XCTAssertNil(HistoryLimitInput.parse("0"))
        XCTAssertNil(HistoryLimitInput.parse("201"))
    }
}
```

- [ ] **Step 2: Run the parser tests and confirm the type is missing**

Run:

```bash
swift test --filter HistoryLimitInputTests
```

Expected: compilation fails because `HistoryLimitInput` does not exist.

- [ ] **Step 3: Implement strict parsing**

Create `Sources/Cliplet/HistoryLimitInput.swift`:

```swift
import Foundation

enum HistoryLimitInput {
    static let supportedRange = 1...200

    static func parse(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let parsed = Int(trimmed),
              supportedRange.contains(parsed) else {
            return nil
        }
        return parsed
    }
}
```

- [ ] **Step 4: Reject invalid preference-field values**

Replace `controlTextDidEndEditing` with:

```swift
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
```

- [ ] **Step 5: Confirm clear-history actions**

Replace `AppDelegate.clearHistory()` with:

```swift
@objc private func clearHistory() {
    let alert = NSAlert()
    alert.messageText = "Clear clipboard history?"
    alert.informativeText = "This permanently removes all saved text and images."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Cancel")
    alert.addButton(withTitle: "Clear History")

    NSApp.activate(ignoringOtherApps: true)
    guard alert.runModal() == .alertSecondButtonReturn else {
        return
    }

    history.clear()
    NotificationCenter.default.post(name: .clipboardHistoryDidChange, object: nil)
}
```

- [ ] **Step 6: Run AppKit tests**

Run:

```bash
swift test --filter HistoryLimitInputTests
swift test --filter ClipletTests
```

Expected: all AppKit test cases pass.

- [ ] **Step 7: Commit destructive-operation protection**

```bash
git add Sources/Cliplet/HistoryLimitInput.swift Sources/Cliplet/PreferencesWindowController.swift Sources/Cliplet/AppDelegate.swift Tests/ClipletTests/HistoryLimitInputTests.swift
git commit -m "Protect destructive history actions"
```

---

### Task 5: Verify the Integrated Application Change

**Files:**
- Review: `Sources/ClipletCore/ClipboardHistory.swift`
- Review: `Sources/Cliplet/ClipboardSelectionService.swift`
- Review: `Sources/Cliplet/AutoPasteController.swift`
- Review: `Sources/Cliplet/ClipboardPanelController.swift`
- Review: `Sources/Cliplet/PreferencesWindowController.swift`
- Review: `Sources/Cliplet/AppDelegate.swift`

**Interfaces:**
- Consumes: all interfaces produced by Tasks 1–4.
- Produces: a tested application commit ready for release-engineering work.

- [ ] **Step 1: Run formatting and diff checks**

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; only intended files are modified or committed.

- [ ] **Step 2: Run the complete test suite**

```bash
swift test
```

Expected: all Core and AppKit tests pass. On the current Command Line Tools-only machine, defer this exact command to GitHub CI and record the local XCTest limitation rather than claiming a local pass.

- [ ] **Step 3: Build debug and release products**

```bash
swift build
swift build -c release
```

Expected: both builds finish with exit code 0 and no new project-source warnings.

- [ ] **Step 4: Inspect the final application diff**

```bash
git diff HEAD~4 -- Sources Tests Package.swift
```

Expected: the diff contains only promotion/deduplication, selection writing, automatic-paste safety, destructive-operation protection, and their tests.
