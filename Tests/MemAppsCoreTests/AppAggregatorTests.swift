import MemAppsCore
import XCTest

final class AppAggregatorTests: XCTestCase {
    func testAggregateByGroupKey() {
        let records = [
            ProcessRecord(groupKey: "bundle:com.apple.Terminal", name: "Terminal", bundleId: "com.apple.Terminal", footprintBytes: 100),
            ProcessRecord(groupKey: "bundle:com.apple.Terminal", name: "Terminal", bundleId: "com.apple.Terminal", footprintBytes: 300),
            ProcessRecord(groupKey: "bundle:com.google.Chrome", name: "Google Chrome", bundleId: "com.google.Chrome", footprintBytes: 200),
        ]

        let result = AppAggregator.aggregate(records)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "Terminal")
        XCTAssertEqual(result[0].footprintBytes, 400)
        XCTAssertEqual(result[0].processCount, 2)
        XCTAssertEqual(result[1].name, "Google Chrome")
    }

    func testFilteredTop() {
        let apps = [
            AppAggregate(name: "A", bundleId: nil, footprintBytes: 1000, processCount: 1),
            AppAggregate(name: "B", bundleId: nil, footprintBytes: 500, processCount: 1),
            AppAggregate(name: "C", bundleId: nil, footprintBytes: 100, processCount: 1),
        ]

        let result = AppAggregator.filteredTop(apps, minBytes: 200, top: 2)
        XCTAssertEqual(result.map(\.name), ["A", "B"])
    }

    func testMegabytesToBytes() {
        XCTAssertEqual(MemoryUnits.megabytesToBytes(1), 1_048_576)
        XCTAssertEqual(MemoryUnits.megabytesToBytes(0), 0)
    }
}
