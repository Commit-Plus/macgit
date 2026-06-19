import XCTest
@testable import macgit

@MainActor
final class FileStatusRowQuickActionTests: XCTestCase {
    func testChangedRowsUsePlusStageAction() {
        let action = FileStatusRowQuickAction(isStaged: false)

        XCTAssertEqual(action.systemImage, "plus")
        XCTAssertEqual(action.accessibilityLabel, "Stage file")
        XCTAssertEqual(action.kind, .stage)
    }

    func testStagedRowsUseMinusUnstageAction() {
        let action = FileStatusRowQuickAction(isStaged: true)

        XCTAssertEqual(action.systemImage, "minus")
        XCTAssertEqual(action.accessibilityLabel, "Unstage file")
        XCTAssertEqual(action.kind, .unstage)
    }
}
