import XCTest
@testable import macgit

final class RepoPickerViewTests: XCTestCase {
    func testVisibleRepositoriesDefaultsToLastOpenedDescending() {
        let older = makeRepository(name: "Zeta", path: "/tmp/zeta", lastOpened: Date(timeIntervalSince1970: 100))
        let newer = makeRepository(name: "Alpha", path: "/tmp/alpha", lastOpened: Date(timeIntervalSince1970: 200))

        let visible = RepoPickerView.visibleRepositories(
            from: [older, newer],
            searchText: "",
            sortOption: .lastOpened,
            selectedFilterTypes: [],
            repoIcons: [:],
            rowStates: [:]
        )

        XCTAssertEqual(visible.map { $0.name }, ["Alpha", "Zeta"])
    }

    func testVisibleRepositoriesSortsByNameWhenRequested() {
        let zebra = makeRepository(name: "zebra", path: "/tmp/zebra", lastOpened: Date(timeIntervalSince1970: 300))
        let alpha = makeRepository(name: "Alpha", path: "/tmp/alpha", lastOpened: Date(timeIntervalSince1970: 100))

        let visible = RepoPickerView.visibleRepositories(
            from: [zebra, alpha],
            searchText: "",
            sortOption: .name,
            selectedFilterTypes: [],
            repoIcons: [:],
            rowStates: [:]
        )

        XCTAssertEqual(visible.map { $0.name }, ["Alpha", "zebra"])
    }

    func testVisibleRepositoriesMatchesBranchAndPathSearchText() {
        let worktreeRepo = makeRepository(
            name: "Workbench",
            path: "/Users/test/Work/Workbench",
            lastOpened: Date(timeIntervalSince1970: 100)
        )
        let docsRepo = makeRepository(
            name: "Docs",
            path: "/Users/test/Notes/Docs",
            lastOpened: Date(timeIntervalSince1970: 200)
        )
        let rowStates = [
            worktreeRepo.url: RepoPickerRowState(currentBranch: "feature/repo-picker", isMissing: false, isLoading: false),
            docsRepo.url: RepoPickerRowState(currentBranch: "main", isMissing: false, isLoading: false)
        ]

        let branchMatch = RepoPickerView.visibleRepositories(
            from: [worktreeRepo, docsRepo],
            searchText: "repo-picker",
            sortOption: .lastOpened,
            selectedFilterTypes: [],
            repoIcons: [:],
            rowStates: rowStates
        )
        let pathMatch = RepoPickerView.visibleRepositories(
            from: [worktreeRepo, docsRepo],
            searchText: "notes/docs",
            sortOption: .lastOpened,
            selectedFilterTypes: [],
            repoIcons: [:],
            rowStates: rowStates
        )

        XCTAssertEqual(branchMatch.map { $0.name }, ["Workbench"])
        XCTAssertEqual(pathMatch.map { $0.name }, ["Docs"])
    }

    private func makeRepository(name: String, path: String, lastOpened: Date) -> RecentRepository {
        var repo = RecentRepository(url: URL(fileURLWithPath: path), lastOpened: lastOpened)
        repo.name = name
        return repo
    }
}
