import XCTest
@testable import macgit

final class GitCurrentBranchResolverTests: XCTestCase {
    func testResolveUsesShowCurrentWhenAvailable() {
        let branch = GitCurrentBranchResolver.resolve(
            showCurrentOutput: "feature/current\n",
            abbreviatedHeadOutput: "main\n"
        )

        XCTAssertEqual(branch, "feature/current")
    }

    func testResolveFallsBackToAbbreviatedHeadWhenShowCurrentIsEmpty() {
        let branch = GitCurrentBranchResolver.resolve(
            showCurrentOutput: "\n",
            abbreviatedHeadOutput: "feature/2026/v1/implement-storage\n"
        )

        XCTAssertEqual(branch, "feature/2026/v1/implement-storage")
    }

    func testResolveTreatsHeadFallbackAsDetachedHead() {
        let branch = GitCurrentBranchResolver.resolve(
            showCurrentOutput: "",
            abbreviatedHeadOutput: "HEAD\n"
        )

        XCTAssertNil(branch)
    }
}
