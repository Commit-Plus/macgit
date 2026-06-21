import XCTest
@testable import macgit

final class SidebarTreeBuilderTests: XCTestCase {
    func testBuildTreeGroupsSlashDelimitedRefs() {
        let nodes = SidebarTreeBuilder.buildTree(from: [
            "main",
            "feature/login",
            "feature/sidebar/remotes"
        ])

        XCTAssertEqual(nodes.map(\.name), ["feature", "main"])
        XCTAssertTrue(nodes[0].isFolder)
        XCTAssertEqual(nodes[0].children.map(\.name), ["sidebar", "login"])
        XCTAssertEqual(nodes[0].children[0].children.map(\.fullPath), ["feature/sidebar/remotes"])
    }

    func testRemoteTreeUsesRemoteAsTopLevelFolderAndNormalizesHead() {
        let nodes = SidebarTreeBuilder.buildRemoteTree(remoteBranchesByRemote: [
            "origin": ["HEAD -> origin/main", "main", "feature/api"],
            "upstream": ["develop"]
        ])

        XCTAssertEqual(nodes.map(\.name), ["origin", "upstream"])
        XCTAssertEqual(nodes[0].fullPath, "origin")
        XCTAssertTrue(nodes[0].isFolder)
        XCTAssertEqual(nodes[0].children.map(\.name), ["feature", "HEAD", "main"])
        XCTAssertEqual(nodes[0].children.first { $0.name == "HEAD" }?.fullPath, "origin/HEAD")
        XCTAssertEqual(nodes[0].children.first { $0.name == "main" }?.fullPath, "origin/main")
    }

    func testExpandedFolderPathsRevealCurrentBranchAncestorsOnly() {
        let paths = SidebarTreeBuilder.expandedFolderPaths(
            revealing: "feature/2026/v1/implement-storage"
        )

        XCTAssertEqual(paths, [
            "feature",
            "feature/2026",
            "feature/2026/v1"
        ])
    }

    func testVisibleRowsIncludeNestedCurrentBranchWhenAncestorFoldersAreExpanded() {
        let nodes = SidebarTreeBuilder.buildTree(from: [
            "master",
            "feature/2026/v1/implement-storage",
            "feature/2026/v2/update-search",
            "test/sidebar"
        ])
        let expandedFolders = SidebarTreeBuilder.expandedFolderPaths(
            revealing: "feature/2026/v1/implement-storage"
        )

        let rows = SidebarTreeBuilder.visibleRows(from: nodes, expandedFolders: expandedFolders)

        XCTAssertTrue(rows.contains { $0.fullPath == "feature/2026/v1/implement-storage" })
        XCTAssertFalse(rows.contains { $0.fullPath == "feature/2026/v2/update-search" })
        XCTAssertFalse(rows.contains { $0.fullPath == "test/sidebar" })
    }
}
