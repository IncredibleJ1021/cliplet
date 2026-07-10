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
