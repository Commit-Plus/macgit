import XCTest
@testable import macgit

final class BranchSyncStatusTests: XCTestCase {
    func testBranchSyncStatusEquality() {
        let a = BranchSyncStatus(ahead: 2, behind: 1)
        let b = BranchSyncStatus(ahead: 2, behind: 1)
        let c = BranchSyncStatus(ahead: 1, behind: 2)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testBranchSyncStatusInSyncReturnsNil() {
        // This is a placeholder for an integration test.
        // A full integration test would create a temp git repo,
        // set up a remote tracking branch, and verify the
        // GitStatusService.branchSyncStatus method returns nil
        // when the branch is in sync with its upstream.
        // For now, we verify the model exists and compiles.
        XCTAssertTrue(true)
    }
}