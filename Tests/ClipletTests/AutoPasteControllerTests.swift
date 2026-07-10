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

    func testTargetBecomesUnavailableWhileWaitingDoesNotPost() {
        var availabilityChecks = 0
        var postCount = 0
        let controller = makeController(
            isApplicationAvailable: { _ in
                availabilityChecks += 1
                return availabilityChecks == 1
            },
            postCommandV: { postCount += 1; return true }
        )
        var result: AutoPasteResult?

        controller.paste(to: .current) { result = $0 }

        XCTAssertEqual(result, .targetUnavailable)
        XCTAssertEqual(postCount, 0)
    }

    func testTimesOutWithoutPosting() {
        var monotonicTime: TimeInterval = 0
        var postCount = 0
        let controller = makeController(
            frontmostPID: { nil },
            postCommandV: { postCount += 1; return true },
            activationTimeout: 0.04,
            pollInterval: 0.02,
            now: { monotonicTime },
            schedule: { delay, action in
                monotonicTime += delay
                action()
            }
        )
        var result: AutoPasteResult?

        controller.paste(to: .current) { result = $0 }

        XCTAssertEqual(result, .activationTimedOut)
        XCTAssertEqual(postCount, 0)
    }

    func testDelayedPollPastDeadlineTimesOutWithoutPosting() {
        let target = NSRunningApplication.current
        var monotonicTime: TimeInterval = 0
        var postCount = 0
        let controller = makeController(
            frontmostPID: {
                monotonicTime >= 1 ? target.processIdentifier : nil
            },
            postCommandV: { postCount += 1; return true },
            activationTimeout: 0.5,
            now: { monotonicTime },
            schedule: { _, action in
                monotonicTime = 1
                action()
            }
        )
        var result: AutoPasteResult?

        controller.paste(to: target) { result = $0 }

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
        pollInterval: TimeInterval = 0.02,
        now: @escaping () -> TimeInterval = { 0 },
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { _, action in action() }
    ) -> AutoPasteController {
        let environment = AutoPasteEnvironment(
            isTrusted: { isTrusted },
            isApplicationAvailable: isApplicationAvailable,
            activate: activate,
            frontmostPID: frontmostPID,
            postCommandV: postCommandV,
            now: now,
            schedule: schedule
        )
        return AutoPasteController(
            environment: environment,
            activationTimeout: activationTimeout,
            pollInterval: pollInterval
        )
    }
}
