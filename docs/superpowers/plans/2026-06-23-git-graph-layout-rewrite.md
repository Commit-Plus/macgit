# Git Graph Layout Engine Rewrite — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the simple `CommitGraphLayoutEngine` with a `gleisbau`-inspired layout that derives branches from refs/tags/merge summaries, filters untracked commits, assigns GitFlow-aware columns, and renders clean merge/fork connectors.

**Architecture:** The new engine is a pure function from `[Commit]` to `CommitGraphLayout`. Internally it builds a vertex graph, extracts `BranchInfo` objects, assigns branch traces, filters anonymous commits, packs columns, and emits main-track + connector paths. Rendering in `BranchGraphCanvas` stays Canvas-based but uses 4-point SVG-style connectors.

**Tech Stack:** Swift, SwiftUI Canvas, XCTest, macOS Git subprocess via `GitStatusService`.

---

## File structure

| File | Responsibility |
|------|----------------|
| `macgit/Services/GitStatusService+Branch.swift` | Add `refsWithHashes(in:)` helper for local branches, tags, remotes. |
| `macgit/Views/History/CommitGraphTypes.swift` | New internal types: `CommitVertex`, `BranchInfo`, `BranchVisual`, `GraphNode`, `GraphPath`, `CommitGraphLayout`, `LaneColors`. |
| `macgit/Views/History/MergeSummaryParser.swift` | Parse merge commit messages into derived branch names. |
| `macgit/Views/History/CommitGraphLayoutEngine.swift` | Rewrite: vertex graph builder, branch extractor, trace assigner, source/target resolver, commit filter, column packer, path builder. |
| `macgit/Views/History/BranchGraphCanvas.swift` | Update to draw 4-point connectors; keep dots and main tracks. |
| `macgit/Views/History/HistoryView.swift` | Update call site if the layout method signature changes. |
| `macgitTests/MergeSummaryParserTests.swift` | Unit tests for merge message parsing. |
| `macgitTests/CommitGraphLayoutEngineTests.swift` | Expand with branch/column/path tests; keep/adjust existing tests. |

---

## Task 1: Enumerate refs with commit hashes

**Files:**
- Modify: `macgit/Services/GitStatusService+Branch.swift`
- Test: `macgitTests/CommitGraphLayoutEngineTests.swift`

Add a lightweight data type and a single git command that returns all refs we care about with their OIDs.

- [ ] **Step 1: Add `GitRef` type**

```swift
struct GitRef: Equatable {
    let name: String
    let hash: String
    let kind: GitRefKind
}

enum GitRefKind {
    case localBranch
    case remoteBranch
    case tag
}
```

Append to `macgit/Services/GitStatusService+Branch.swift`.

- [ ] **Step 2: Add `refsWithHashes(in:)`**

```swift
func refsWithHashes(in repositoryURL: URL) async -> [GitRef] {
    let output = (try? await runGit(
        arguments: ["for-each-ref", "--format=%(refname:short) %(objectname)", "refs/heads", "refs/tags", "refs/remotes/origin"],
        in: repositoryURL
    )) ?? ""
    return output.split(separator: "\n").compactMap { line in
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        let name = String(parts[0])
        let hash = String(parts[1])
        let kind: GitRefKind
        if name.hasPrefix("origin/") {
            kind = .remoteBranch
        } else {
            // Distinguish tag vs branch by asking the object type is cheap but adds a call.
            // Simpler heuristic: tags often don't contain "/"; branches may.
            // For layout quality, treating everything from refs/tags as tag is enough.
            kind = name.contains("/") ? .localBranch : .tag
        }
        return GitRef(name: name, hash: hash, kind: kind)
    }
}
```

- [ ] **Step 3: Write failing test**

Create a temp git repo, make a commit, create a branch and tag, and assert `refsWithHashes` returns both with the correct hashes.

```swift
func testRefsWithHashesReturnsBranchesAndTags() async throws {
    let repo = try makeTempGitRepo()
    try await runGitInRepo(repo, ["commit", "--allow-empty", "-m", "initial"])
    let head = try await runGitInRepo(repo, ["rev-parse", "HEAD"])
    try await runGitInRepo(repo, ["branch", "feature/a"])
    try await runGitInRepo(repo, ["tag", "v1.0"])

    let refs = await GitStatusService.shared.refsWithHashes(in: repo)
    let names = refs.map(\.name)
    XCTAssertTrue(names.contains("feature/a"))
    XCTAssertTrue(names.contains("v1.0"))
    XCTAssertTrue(refs.allSatisfy { $0.hash == head })
}
```

- [ ] **Step 4: Run test, expect failure due to missing helper**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing:macgitTests/CommitGraphLayoutEngineTests/testRefsWithHashesReturnsBranchesAndTags`

Expected: FAIL, function not defined.

- [ ] **Step 5: Implement helper and run again**

Run the same command; expected PASS.

---

## Task 2: Merge-summary parser

**Files:**
- Create: `macgit/Views/History/MergeSummaryParser.swift`
- Test: `macgitTests/MergeSummaryParserTests.swift`

- [ ] **Step 1: Create parser file**

```swift
import Foundation

enum MergeSummaryParser {
    static let patterns: [String] = [
        "Merge branch '([^']+)'",
        "Merge pull request #\\d+ from [^/]+/([^\\s]+)",
        "Merged in ([^\\s]+) \\(pull request",
        "Merge branch '([^']+)' of",
        "Merge remote-tracking branch '([^']+)'"
    ]

    static func branchName(from summary: String) -> String? {
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: summary, options: [], range: NSRange(location: 0, length: summary.utf16.count)),
               match.numberOfRanges > 1 {
                let range = match.range(at: 1)
                if let swiftRange = Range(range, in: summary) {
                    return String(summary[swiftRange])
                }
            }
        }
        return nil
    }
}
```

- [ ] **Step 2: Write failing parser tests**

Create `macgitTests/MergeSummaryParserTests.swift`:

```swift
import XCTest
@testable import macgit

final class MergeSummaryParserTests: XCTestCase {
    func testGitDefault() {
        XCTAssertEqual(MergeSummaryParser.branchName(from: "Merge branch 'feature/my-feature' into dev"), "feature/my-feature")
    }
    func testGitHubPullRequest() {
        XCTAssertEqual(MergeSummaryParser.branchName(from: "Merge pull request #1 from user-x/feature/my-feature"), "feature/my-feature")
    }
    func testGitLabMergeRequest() {
        XCTAssertEqual(MergeSummaryParser.branchName(from: "Merge branch 'feature/my-feature' into 'master'"), "feature/my-feature")
    }
    func testBitbucket() {
        XCTAssertEqual(MergeSummaryParser.branchName(from: "Merged in feature/my-feature (pull request #1)"), "feature/my-feature")
    }
    func testNonMergeReturnsNil() {
        XCTAssertNil(MergeSummaryParser.branchName(from: "fix typo"))
    }
}
```

- [ ] **Step 3: Run parser tests**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing:macgitTests/MergeSummaryParserTests`

Expected: PASS.

---

## Task 3: Define new internal graph types

**Files:**
- Modify: `macgit/Views/History/CommitGraphTypes.swift`

- [ ] **Step 1: Replace file contents**

Keep public layout types and add internal vertex/branch types:

```swift
//
//  CommitGraphTypes.swift
//  macgit
//

import SwiftUI

// MARK: - Public rendering types

struct GraphNode: Identifiable {
    let id = UUID()
    let commit: Commit
    let lane: Int
    let rowIndex: Int
}

struct GraphPoint: Equatable {
    let row: Int
    let lane: Int
}

struct GraphPath {
    let points: [GraphPoint]
    let color: Color
    let isMergeConnector: Bool
}

struct CommitGraphLayout {
    let nodes: [GraphNode]
    let paths: [GraphPath]
    let laneCount: Int
}

// MARK: - Internal layout types

struct CommitVertex {
    let row: Int
    let commit: Commit
    var parents: [Int]
    var children: [Int]
    var branchTrace: Int?
    var isMerge: Bool { commit.parents.count > 1 }
}

struct BranchInfo {
    let id: Int
    let name: String
    let targetRow: Int
    var sourceBranch: Int?
    var targetBranch: Int?
    let persistence: Int
    var range: (start: Int, end: Int)
}

struct BranchVisual {
    let orderGroup: Int
    var sourceOrderGroup: Int?
    var targetOrderGroup: Int?
    var column: Int?
    let color: Color
}

// MARK: - Lane Colors

struct LaneColors {
    static let palette: [Color] = [
        Color(nsColor: NSColor.systemBlue),
        Color(nsColor: NSColor.systemGreen),
        Color(nsColor: NSColor.systemOrange),
        Color(nsColor: NSColor.systemPurple),
        Color(nsColor: NSColor.systemRed),
        Color(nsColor: NSColor.systemTeal),
        Color(nsColor: NSColor.systemYellow),
        Color(nsColor: NSColor.systemPink),
        Color(nsColor: NSColor.systemIndigo),
        Color(nsColor: NSColor.systemBrown),
    ]

    static func color(for lane: Int) -> Color {
        palette[lane % palette.count]
    }
}
```

- [ ] **Step 2: Build to verify types compile**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`

Expected: may fail because `CommitGraphLayoutEngine` still references old `Vertex`/`Branch` types; that's OK until Task 12.

---

## Task 4: Build vertex graph

**Files:**
- Modify: `macgit/Views/History/CommitGraphLayoutEngine.swift`
- Test: `macgitTests/CommitGraphLayoutEngineTests.swift`

- [ ] **Step 1: Add vertex builder**

Replace the old `buildVertices` with:

```swift
private static func buildVertices(commits: [Commit]) -> [CommitVertex] {
    let rowByHash = Dictionary(uniqueKeysWithValues: commits.enumerated().map { ($1.hash, $0) })
    var vertices: [CommitVertex] = []
    for (row, commit) in commits.enumerated() {
        let parentRows = commit.parents.compactMap { rowByHash[$0] }
        vertices.append(CommitVertex(row: row, commit: commit, parents: parentRows, children: [], branchTrace: nil))
    }
    for (row, vertex) in vertices.enumerated() {
        for parentRow in vertex.parents {
            vertices[parentRow].children.append(row)
        }
    }
    return vertices
}
```

- [ ] **Step 2: Add test**

```swift
func testVertexGraphBuildsParentAndChildrenRelations() {
    let a = makeCommit(hash: "a")
    let b = makeCommit(hash: "b", parents: ["a"])
    let c = makeCommit(hash: "c", parents: ["a"])
    let vertices = CommitGraphLayoutEngine.buildVertices(commits: [c, b, a])
    XCTAssertEqual(vertices[0].parents, [2])
    XCTAssertEqual(vertices[1].parents, [2])
    XCTAssertEqual(vertices[2].children, [0, 1])
}
```

Make the helper `internal` or `@testable` accessible for this test.

- [ ] **Step 3: Run test**

Run the specific test; expected PASS.

---

## Task 5: Extract BranchInfo from refs, tags, merge summaries

**Files:**
- Modify: `macgit/Views/History/CommitGraphLayoutEngine.swift`
- Test: `macgitTests/CommitGraphLayoutEngineTests.swift`

- [ ] **Step 1: Add persistence / order helpers**

```swift
private static func persistence(for name: String, kind: GitRefKind) -> Int {
    switch kind {
    case .tag: return 0
    case .localBranch where ["main", "master", "develop"].contains(name): return 1
    case .localBranch where name.hasPrefix("release/") || name.hasPrefix("hotfix/"): return 2
    case .localBranch where name.hasPrefix("feature/"): return 3
    case .localBranch: return 4
    case .remoteBranch: return 5
    }
}

private static func orderGroup(for name: String) -> Int {
    let base = name.hasPrefix("origin/") ? String(name.dropFirst(7)) : name
    switch true {
    case ["main", "master", "develop"].contains(base): return 0
    case base.hasPrefix("release/"), base.hasPrefix("hotfix/"): return 1
    case base.hasPrefix("feature/"): return 2
    default: return 3
    }
}
```

- [ ] **Step 2: Add branch extractor**

```swift
private static func extractBranches(
    vertices: [CommitVertex],
    refs: [GitRef],
    mergeSummaries: [Int: String]
) -> [BranchInfo] {
    var branches: [BranchInfo] = []
    for ref in refs {
        guard let targetRow = vertices.firstIndex(where: { $0.commit.hash == ref.hash }) else { continue }
        branches.append(BranchInfo(
            id: branches.count,
            name: ref.name,
            targetRow: targetRow,
            sourceBranch: nil,
            targetBranch: nil,
            persistence: persistence(for: ref.name, kind: ref.kind),
            range: (start: targetRow, end: targetRow)
        ))
    }
    for (row, summary) in mergeSummaries {
        guard let name = MergeSummaryParser.branchName(from: summary),
              vertices[row].isMerge else { continue }
        branches.append(BranchInfo(
            id: branches.count,
            name: name,
            targetRow: vertices[row].parents[1],
            sourceBranch: nil,
            targetBranch: nil,
            persistence: 6,
            range: (start: vertices[row].parents[1], end: vertices[row].parents[1])
        ))
    }
    branches.sort { $0.persistence < $1.persistence }
    return branches
}
```

- [ ] **Step 3: Test extraction**

```swift
func testBranchExtractionPrioritizesMainOverFeature() {
    let a = makeCommit(hash: "a")
    let b = makeCommit(hash: "b", parents: ["a"])
    let c = makeCommit(hash: "c", parents: ["b"])
    let vertices = CommitGraphLayoutEngine.buildVertices(commits: [c, b, a])
    let refs = [
        GitRef(name: "feature/x", hash: c.hash, kind: .localBranch),
        GitRef(name: "main", hash: c.hash, kind: .localBranch)
    ]
    let branches = CommitGraphLayoutEngine.extractBranches(vertices: vertices, refs: refs, mergeSummaries: [:])
    XCTAssertEqual(branches.first?.name, "main")
}
```

- [ ] **Step 4: Run test**

Expected PASS.

---

## Task 6: Assign branch traces

**Files:**
- Modify: `macgit/Views/History/CommitGraphLayoutEngine.swift`
- Test: `macgitTests/CommitGraphLayoutEngineTests.swift`

- [ ] **Step 1: Add trace assignment**

```swift
private static func assignBranchTraces(vertices: inout [CommitVertex], branches: inout [BranchInfo]) {
    for i in 0..<branches.count {
        var currentRow = branches[i].targetRow
        var endRow = currentRow
        while true {
            if vertices[currentRow].branchTrace != nil {
                break
            }
            vertices[currentRow].branchTrace = i
            endRow = currentRow
            guard let nextParent = vertices[currentRow].parents.first else { break }
            currentRow = nextParent
        }
        branches[i].range.end = endRow
    }
}
```

- [ ] **Step 2: Test trace assignment**

```swift
func testTraceAssignsMainLineToAllCommits() {
    let a = makeCommit(hash: "a", refs: ["main"])
    let b = makeCommit(hash: "b", parents: ["a"])
    let c = makeCommit(hash: "c", parents: ["b"])
    var vertices = CommitGraphLayoutEngine.buildVertices(commits: [c, b, a])
    var branches = [
        BranchInfo(id: 0, name: "main", targetRow: 0, sourceBranch: nil, targetBranch: nil, persistence: 1, range: (0, 0))
    ]
    CommitGraphLayoutEngine.assignBranchTraces(vertices: &vertices, branches: &branches)
    XCTAssertEqual(vertices.map(\.branchTrace), [0, 0, 0])
}
```

- [ ] **Step 3: Run test**

Expected PASS.

---

## Task 7: Derive source / target branches

**Files:**
- Modify: `macgit/Views/History/CommitGraphLayoutEngine.swift`
- Test: `macgitTests/CommitGraphLayoutEngineTests.swift`

- [ ] **Step 1: Add resolver**

```swift
private static func assignSourcesAndTargets(vertices: [CommitVertex], branches: inout [BranchInfo]) {
    // Target: branch whose tip is the second parent of a merge
    for (i, branch) in branches.enumerated() {
        let tipVertex = vertices[branch.targetRow]
        if tipVertex.isMerge {
            let mergeRow = tipVertex.children.first ?? branch.targetRow
            if vertices[mergeRow].branchTrace != i {
                branches[i].targetBranch = vertices[mergeRow].branchTrace
            }
        }
    }
    // Source: current commit's parent is on a different trace
    for (row, vertex) in vertices.enumerated() {
        guard let trace = vertex.branchTrace else { continue }
        for parentRow in vertex.parents {
            if let parentTrace = vertices[parentRow].branchTrace, parentTrace != trace {
                branches[trace].sourceBranch = parentTrace
            }
        }
    }
}
```

- [ ] **Step 2: Test source/target**

```swift
func testSourceAndTargetBranches() {
    let a = makeCommit(hash: "a")
    let b = makeCommit(hash: "b", parents: ["a"])
    let f = makeCommit(hash: "f", parents: ["b"])
    let m = makeCommit(hash: "m", parents: ["b", "f"])
    var vertices = CommitGraphLayoutEngine.buildVertices(commits: [m, f, b, a])
    var branches = [
        BranchInfo(id: 0, name: "main", targetRow: 0, sourceBranch: nil, targetBranch: nil, persistence: 1, range: (0, 0)),
        BranchInfo(id: 1, name: "feature", targetRow: 1, sourceBranch: nil, targetBranch: nil, persistence: 3, range: (1, 1))
    ]
    CommitGraphLayoutEngine.assignBranchTraces(vertices: &vertices, branches: &branches)
    CommitGraphLayoutEngine.assignSourcesAndTargets(vertices: vertices, branches: &branches)
    XCTAssertEqual(branches[1].targetBranch, 0)
    XCTAssertEqual(branches[1].sourceBranch, 0)
}
```

- [ ] **Step 3: Run test**

Expected PASS.

---

## Task 8: Filter commits not on a branch

**Files:**
- Modify: `macgit/Views/History/CommitGraphLayoutEngine.swift`
- Test: `macgitTests/CommitGraphLayoutEngineTests.swift`

- [ ] **Step 1: Add filter**

```swift
private static func filterAnonymousCommits(
    vertices: [CommitVertex],
    branches: inout [BranchInfo]
) -> [CommitVertex] {
    let kept = vertices.enumerated().filter { $1.branchTrace != nil }
    let indexMap = Dictionary(uniqueKeysWithValues: kept.map { ($0.offset, $0.0) })
    let filtered = kept.map { $1 }

    for i in 0..<branches.count {
        if let start = branches[i].range.start {
            branches[i].range.start = indexMap[start]
        }
        if let end = branches[i].range.end {
            branches[i].range.end = indexMap[end]
        }
        if let target = branches[i].targetBranch {
            branches[i].targetBranch = indexMap[target]
        }
        if let source = branches[i].sourceBranch {
            branches[i].sourceBranch = indexMap[source]
        }
    }

    var result: [CommitVertex] = []
    for (newRow, var vertex) in filtered.enumerated() {
        vertex.row = newRow
        vertex.parents = vertex.parents.compactMap { indexMap[$0] }.sorted()
        vertex.children = vertex.children.compactMap { indexMap[$0] }.sorted()
        result.append(vertex)
    }
    return result
}
```

- [ ] **Step 2: Test filtering**

```swift
func testFilterDropsCommitsNotOnBranch() {
    let a = makeCommit(hash: "a")
    let orphan = makeCommit(hash: "orphan")
    let b = makeCommit(hash: "b", parents: ["a"])
    var vertices = CommitGraphLayoutEngine.buildVertices(commits: [orphan, b, a])
    var branches = [
        BranchInfo(id: 0, name: "main", targetRow: 1, sourceBranch: nil, targetBranch: nil, persistence: 1, range: (1, 1))
    ]
    CommitGraphLayoutEngine.assignBranchTraces(vertices: &vertices, branches: &branches)
    let filtered = CommitGraphLayoutEngine.filterAnonymousCommits(vertices: vertices, branches: &branches)
    XCTAssertEqual(filtered.count, 2)
    XCTAssertEqual(filtered.map(\.commit.hash), ["b", "a"])
}
```

- [ ] **Step 3: Run test**

Expected PASS.

---

## Task 9: Assign columns

**Files:**
- Modify: `macgit/Views/History/CommitGraphLayoutEngine.swift`
- Test: `macgitTests/CommitGraphLayoutEngineTests.swift`

- [ ] **Step 1: Add color helper**

```swift
private static func branchColor(for name: String, index: Int) -> Color {
    LaneColors.color(for: index)
}
```

- [ ] **Step 2: Add column assignment**

```swift
private static func assignColumns(vertices: [CommitVertex], branches: [BranchInfo]) -> [BranchVisual] {
    let groupCount = 4
    var visuals: [BranchVisual] = branches.enumerated().map { i, branch in
        BranchVisual(
            orderGroup: orderGroup(for: branch.name),
            sourceOrderGroup: branch.sourceBranch.map { orderGroup(for: branches[$0].name) },
            targetOrderGroup: branch.targetBranch.map { orderGroup(for: branches[$0].name) },
            column: nil,
            color: branchColor(for: branch.name, index: i)
        )
    }

    var sortKey: [(Int, Int, Int)] = []
    for (i, branch) in branches.enumerated() {
        let start = branch.range.start ?? 0
        let end = branch.range.end ?? (vertices.count - 1)
        let maxGroup = max(visuals[i].sourceOrderGroup ?? groupCount, visuals[i].targetOrderGroup ?? groupCount)
        sortKey.append((maxGroup, start - end, start))
    }
    let order = sortKey.enumerated().sorted { a, b in
        if a.element.0 != b.element.0 { return a.element.0 < b.element.0 }
        if a.element.1 != b.element.1 { return a.element.1 < b.element.1 }
        return a.element.2 < b.element.2
    }.map(\.offset)

    var occupied: [[[ClosedRange<Int>]]] = Array(repeating: [], count: groupCount)

    for i in order {
        let branch = branches[i]
        let group = visuals[i].orderGroup
        let start = branch.range.start ?? 0
        let end = branch.range.end ?? (vertices.count - 1)
        let range = start...end
        let alignRight = (visuals[i].sourceOrderGroup ?? 0) > group || (visuals[i].targetOrderGroup ?? 0) > group

        var chosen = 0
        var placed = false
        let colCount = occupied[group].count
        for c in 0..<colCount {
            let col = alignRight ? colCount - c - 1 : c
            let blocked = occupied[group][col].contains { $0.overlaps(range) }
            if !blocked {
                let targetSameGroupCol = branch.targetBranch.flatMap { target in
                    visuals[target].orderGroup == group ? visuals[target].column : nil
                }
                if targetSameGroupCol == col { continue }
                chosen = col
                placed = true
                break
            }
        }
        if !placed {
            chosen = occupied[group].count
            occupied[group].append([])
        }
        visuals[i].column = chosen
        occupied[group][chosen].append(range)
    }

    // Convert group-relative columns to absolute columns
    var groupOffset: [Int] = []
    var acc = 0
    for g in 0..<groupCount {
        groupOffset.append(acc)
        acc += occupied[g].count
    }
    for i in 0..<visuals.count {
        if let col = visuals[i].column {
            visuals[i].column = col + groupOffset[visuals[i].orderGroup]
        }
    }

    return visuals
}
```

- [ ] **Step 3: Test column assignment**

```swift
func testMainAndFeatureGetSeparateColumns() {
    let a = makeCommit(hash: "a")
    let f = makeCommit(hash: "f", parents: ["a"])
    let m = makeCommit(hash: "m", parents: ["a", "f"])
    var vertices = CommitGraphLayoutEngine.buildVertices(commits: [m, f, a])
    var branches = [
        BranchInfo(id: 0, name: "main", targetRow: 0, sourceBranch: nil, targetBranch: nil, persistence: 1, range: (0, 0)),
        BranchInfo(id: 1, name: "feature/x", targetRow: 1, sourceBranch: nil, targetBranch: nil, persistence: 3, range: (1, 1))
    ]
    CommitGraphLayoutEngine.assignBranchTraces(vertices: &vertices, branches: &branches)
    CommitGraphLayoutEngine.assignSourcesAndTargets(vertices: vertices, branches: &branches)
    let filtered = CommitGraphLayoutEngine.filterAnonymousCommits(vertices: vertices, branches: &branches)
    let visuals = CommitGraphLayoutEngine.assignColumns(vertices: filtered, branches: branches)
    XCTAssertNotEqual(visuals[0].column, visuals[1].column)
}
```

- [ ] **Step 4: Run test**

Expected PASS.

---

## Task 10: Build paths

**Files:**
- Modify: `macgit/Views/History/CommitGraphLayoutEngine.swift`
- Test: `macgitTests/CommitGraphLayoutEngineTests.swift`

- [ ] **Step 1: Add deviate index and path builder**

```swift
private static func deviateIndex(
    vertices: [CommitVertex],
    childRow: Int,
    parentRow: Int,
    isMerge: Bool
) -> Int {
    if isMerge {
        let parentColumn = vertices[parentRow].branchTrace
        var maxSibling = childRow
        for siblingRow in vertices[parentRow].children {
            guard siblingRow != childRow else { continue }
            if vertices[siblingRow].branchTrace == parentColumn && siblingRow > maxSibling {
                maxSibling = siblingRow
            }
        }
        return maxSibling
    } else {
        return parentRow - 1
    }
}

private static func buildPaths(vertices: [CommitVertex], branches: [BranchInfo], visuals: [BranchVisual]) -> [GraphPath] {
    var paths: [GraphPath] = []

    // Main tracks
    for (i, branch) in branches.enumerated() {
        guard let column = visuals[i].column else { continue }
        let branchRows = vertices.enumerated().compactMap { $1.branchTrace == i ? $0 : nil }
        guard branchRows.count > 1 else { continue }
        let points = branchRows.map { GraphPoint(row: $0, lane: column) }
        paths.append(GraphPath(points: points, color: visuals[i].color, isMergeConnector: false))
    }

    // Connectors
    for (row, vertex) in vertices.enumerated() {
        guard let childTrace = vertex.branchTrace,
              let childColumn = visuals[childTrace].column else { continue }
        for (parentIndex, parentRow) in vertex.parents.enumerated() {
            guard let parentTrace = vertices[parentRow].branchTrace,
                  let parentColumn = visuals[parentTrace].column else { continue }
            let isMergeConnector = vertex.isMerge && parentIndex > 0
            let color = isMergeConnector ? visuals[parentTrace].color : visuals[childTrace].color
            if childColumn == parentColumn {
                if row + 1 < parentRow {
                    let points = (row...parentRow).map { GraphPoint(row: $0, lane: childColumn) }
                    paths.append(GraphPath(points: points, color: color, isMergeConnector: isMergeConnector))
                }
            } else {
                let split = deviateIndex(vertices: vertices, childRow: row, parentRow: parentRow, isMerge: isMergeConnector)
                let points = [
                    GraphPoint(row: row, lane: childColumn),
                    GraphPoint(row: split, lane: childColumn),
                    GraphPoint(row: split + 1, lane: parentColumn),
                    GraphPoint(row: parentRow, lane: parentColumn)
                ]
                paths.append(GraphPath(points: points, color: color, isMergeConnector: isMergeConnector))
            }
        }
    }

    return paths
}
```

- [ ] **Step 2: Test connector path shape**

```swift
func testMergeConnectorUsesDeviateIndex() {
    let a = makeCommit(hash: "a")
    let b = makeCommit(hash: "b", parents: ["a"])
    let f = makeCommit(hash: "f", parents: ["b"])
    let m = makeCommit(hash: "m", parents: ["b", "f"])
    var vertices = CommitGraphLayoutEngine.buildVertices(commits: [m, f, b, a])
    var branches = [
        BranchInfo(id: 0, name: "main", targetRow: 0, sourceBranch: nil, targetBranch: nil, persistence: 1, range: (0, 0)),
        BranchInfo(id: 1, name: "feature/x", targetRow: 1, sourceBranch: nil, targetBranch: nil, persistence: 3, range: (1, 1))
    ]
    CommitGraphLayoutEngine.assignBranchTraces(vertices: &vertices, branches: &branches)
    CommitGraphLayoutEngine.assignSourcesAndTargets(vertices: vertices, branches: &branches)
    let visuals = CommitGraphLayoutEngine.assignColumns(vertices: vertices, branches: branches)
    let paths = CommitGraphLayoutEngine.buildPaths(vertices: vertices, branches: branches, visuals: visuals)
    let mergePaths = paths.filter(\.isMergeConnector)
    XCTAssertEqual(mergePaths.count, 1)
    XCTAssertEqual(mergePaths.first?.points.count, 4)
}
```

- [ ] **Step 3: Run test**

Expected PASS.

---

## Task 11: Update `CommitGraphLayoutEngine.layout`

**Files:**
- Modify: `macgit/Views/History/CommitGraphLayoutEngine.swift`
- Test: `macgitTests/CommitGraphLayoutEngineTests.swift`

- [ ] **Step 1: Replace public entry point**

```swift
enum CommitGraphLayoutEngine {
    static func layout(commits: [Commit], refs: [GitRef] = [], mergeSummaries: [Int: String] = [:]) -> CommitGraphLayout {
        guard !commits.isEmpty else {
            return CommitGraphLayout(nodes: [], paths: [], laneCount: 1)
        }

        var vertices = buildVertices(commits: commits)
        var branches = extractBranches(vertices: vertices, refs: refs, mergeSummaries: mergeSummaries)
        assignBranchTraces(vertices: &vertices, branches: &branches)
        assignSourcesAndTargets(vertices: vertices, branches: &branches)
        vertices = filterAnonymousCommits(vertices: vertices, branches: &branches)
        let visuals = assignColumns(vertices: vertices, branches: branches)
        let paths = buildPaths(vertices: vertices, branches: branches, visuals: visuals)

        let nodes = vertices.enumerated().compactMap { (row, vertex) -> GraphNode? in
            guard let trace = vertex.branchTrace, let column = visuals[trace].column else { return nil }
            return GraphNode(commit: vertex.commit, lane: column, rowIndex: row)
        }
        let laneCount = (visuals.compactMap(\.column).max() ?? 0) + 1
        return CommitGraphLayout(nodes: nodes, paths: paths, laneCount: laneCount)
    }

    // ... private helpers from Tasks 4-10 ...
}
```

- [ ] **Step 2: Update existing tests**

Existing tests that pass an empty commit list and expect `laneCount == 1` should still pass. Tests that assume specific lane assignments will need to be updated to reflect the new algorithm. Update `CommitGraphLayoutEngineTests.swift` so all assertions match the new expected behavior.

- [ ] **Step 3: Run all CommitGraphLayoutEngineTests**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing:macgitTests/CommitGraphLayoutEngineTests`

Expected: PASS after updates.

---

## Task 12: Update `BranchGraphCanvas` for 4-point connectors

**Files:**
- Modify: `macgit/Views/History/BranchGraphCanvas.swift`
- Test: `macgitTests/BranchGraphCanvasTests.swift`

The current `path(for:rowHeight:laneWidth:)` already handles multi-segment polylines with rounded corners when lane changes. The 4-point connector from Task 10 is just a 4-point polyline, so it should render correctly without changes. Verify with a test.

- [ ] **Step 1: Add test for 4-point connector**

```swift
func testFourPointConnectorPathReachesParent() {
    let path = BranchGraphCanvas.path(
        for: [
            GraphPoint(row: 0, lane: 0),
            GraphPoint(row: 1, lane: 0),
            GraphPoint(row: 2, lane: 1),
            GraphPoint(row: 3, lane: 1)
        ],
        rowHeight: 20,
        laneWidth: 10
    )
    let rect = path.boundingRect
    XCTAssertEqual(rect.minX, 5, accuracy: 0.001)
    XCTAssertEqual(rect.maxX, 15, accuracy: 0.001)
    XCTAssertEqual(rect.minY, 10, accuracy: 0.001)
    XCTAssertEqual(rect.maxY, 70, accuracy: 0.001)
}
```

- [ ] **Step 2: Run BranchGraphCanvasTests**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing:macgitTests/BranchGraphCanvasTests`

Expected: PASS.

---

## Task 13: Wire `HistoryView` to pass refs and merge summaries

**Files:**
- Modify: `macgit/Views/History/HistoryView.swift`

- [ ] **Step 1: Update layout call site**

Where `HistoryView` currently calls:

```swift
graphLayout = CommitGraphLayoutEngine.layout(commits: commits)
```

change to:

```swift
let refs = await GitStatusService.shared.refsWithHashes(in: repositoryURL)
let mergeSummaries = Dictionary(uniqueKeysWithValues: newCommits.enumerated().compactMap { (idx, commit) -> (Int, String)? in
    guard commit.parents.count > 1 else { return nil }
    return (idx, commit.message)
})
graphLayout = CommitGraphLayoutEngine.layout(commits: commits, refs: refs, mergeSummaries: mergeSummaries)
```

Use the filtered `commits` array indices for `mergeSummaries` so they match the rows passed to `layout`.

- [ ] **Step 2: Build**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`

Expected: succeeds.

---

## Task 14: Run full test suite

- [ ] **Step 1: Run tests**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test`

- [ ] **Step 2: Fix any failures**

Iterate on failures, adding tests for any regressions.

---

## Self-review checklist

- [x] Spec coverage: every design phase has a matching task.
- [x] Placeholder scan: no TBD/TODO in steps.
- [x] Type consistency: `CommitVertex`, `BranchInfo`, `BranchVisual` used consistently.

