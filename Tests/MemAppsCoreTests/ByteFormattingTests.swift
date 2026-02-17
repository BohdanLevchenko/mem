import MemAppsCore
import XCTest

final class ByteFormattingTests: XCTestCase {
    func testHumanReadableBaseUnits() {
        XCTAssertEqual(ByteFormatting.humanReadable(0), "0 B")
        XCTAssertEqual(ByteFormatting.humanReadable(1024), "1 KB")
        XCTAssertEqual(ByteFormatting.humanReadable(1024 * 1024), "1 MB")
    }

    func testHumanReadableFractionalOutput() {
        XCTAssertEqual(ByteFormatting.humanReadable(1536), "1.5 KB")
    }

    func testRawFormatting() {
        XCTAssertEqual(ByteFormatting.format(bytes: 1234, raw: true), "1234")
    }
}
