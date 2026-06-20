import XCTest
@testable import macgit

final class GitUndoToolbarPolicyTests: XCTestCase {
    func testUndoButtonIsEnabledOnlyWhenThereIsUndoWorkAndNoSyncIsRunning() {
        XCTAssertFalse(GitUndoToolbarPolicy.isUndoDisabled(isSyncing: false, canUndo: true))
        XCTAssertTrue(GitUndoToolbarPolicy.isUndoDisabled(isSyncing: true, canUndo: true))
        XCTAssertTrue(GitUndoToolbarPolicy.isUndoDisabled(isSyncing: false, canUndo: false))
        XCTAssertTrue(GitUndoToolbarPolicy.isUndoDisabled(isSyncing: true, canUndo: false))
    }
}
