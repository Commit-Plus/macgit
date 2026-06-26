import XCTest
@testable import macgit

final class SidebarBranchSyncBadgeResolverTests: XCTestCase {
    func testCurrentBranchPrefersFallbackStatus() {
        let resolved = SidebarBranchSyncBadgeResolver.status(
            for: "main",
            currentBranch: "main",
            branchSyncStatus: ["main": BranchSyncStatus(ahead: 0, behind: 0)],
            currentBranchFallbackSyncStatus: BranchSyncStatus(ahead: 2, behind: 1)
        )

        XCTAssertEqual(resolved, BranchSyncStatus(ahead: 2, behind: 1))
    }

    func testCurrentBranchFallsBackToCachedStatusWhenToolbarStatusMissing() {
        let resolved = SidebarBranchSyncBadgeResolver.status(
            for: "main",
            currentBranch: "main",
            branchSyncStatus: ["main": BranchSyncStatus(ahead: 1, behind: 0)],
            currentBranchFallbackSyncStatus: nil
        )

        XCTAssertEqual(resolved, BranchSyncStatus(ahead: 1, behind: 0))
    }

    func testNonCurrentBranchUsesCachedStatus() {
        let resolved = SidebarBranchSyncBadgeResolver.status(
            for: "feature/demo",
            currentBranch: "main",
            branchSyncStatus: ["feature/demo": BranchSyncStatus(ahead: 3, behind: 0)],
            currentBranchFallbackSyncStatus: BranchSyncStatus(ahead: 1, behind: 0)
        )

        XCTAssertEqual(resolved, BranchSyncStatus(ahead: 3, behind: 0))
    }
}
