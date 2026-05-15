import XCTest
@testable import Nimbus

/// XCTest (not Swift Testing) because `measure {}` is XCTest-only.
/// Gates pillar 4's "10k-item directory load ≤ 200ms" for the Phase 2d
/// data-source path. The 120fps SCROLL claim is not unit-testable and
/// is verified manually via Instruments (recorded in the exit-gate doc).
final class FileTablePerfTests: XCTestCase {
    @MainActor
    func testReload10kItemsDataSourceWithinBudget() {
        measure {
            BenchScenarios.reload10kIntoDataSource()
        }
    }
}
