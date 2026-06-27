import XCTest
@testable import macgit

@MainActor
final class BranchSheetInitialStateTests: XCTestCase {
    func testDefaultInitialStatePrefersWorkingCopyParentWhenNoStartPointIsInjected() {
        let state = BranchSheetView.initialCreateState(
            initialStartPoint: nil,
            recentCommits: [
                BranchCommitInfo(hash: "abc123", message: "Latest commit")
            ]
        )

        XCTAssertTrue(state.useWorkingCopyParent)
        XCTAssertNil(state.selectedStartPoint)
    }

    func testInjectedCommitStartPointPreselectsCommitAndDisablesWorkingCopyParent() {
        let state = BranchSheetView.initialCreateState(
            initialStartPoint: .commit(hash: "def456", message: "Dragged commit"),
            recentCommits: [
                BranchCommitInfo(hash: "abc123", message: "Latest commit"),
                BranchCommitInfo(hash: "def456", message: "Dragged commit")
            ]
        )

        XCTAssertFalse(state.useWorkingCopyParent)
        XCTAssertEqual(state.selectedStartPoint, .commit(hash: "def456", message: "Dragged commit"))
        XCTAssertEqual(state.selectedStartReference, "def456")
    }

    func testInjectedBranchStartPointRemainsDistinctForFutureBranchBasedStartSelection() {
        let state = BranchSheetView.initialCreateState(
            initialStartPoint: .branch("release/1.0"),
            recentCommits: [
                BranchCommitInfo(hash: "abc123", message: "Latest commit")
            ]
        )

        XCTAssertFalse(state.useWorkingCopyParent)
        XCTAssertEqual(state.selectedStartPoint, .branch("release/1.0"))
        XCTAssertEqual(state.selectedStartReference, "release/1.0")
    }

    func testInjectedCommitNotPresentInRecentCommitsStillSelectsHashCleanly() {
        let state = BranchSheetView.initialCreateState(
            initialStartPoint: .commit(hash: "deadbeef", message: "Detached selection"),
            recentCommits: [
                BranchCommitInfo(hash: "abc123", message: "Latest commit")
            ]
        )

        XCTAssertFalse(state.useWorkingCopyParent)
        XCTAssertEqual(state.selectedStartPoint, .commit(hash: "deadbeef", message: "Detached selection"))
        XCTAssertEqual(state.selectedStartReference, "deadbeef")
    }
}
