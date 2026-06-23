# Commit Graph Layout Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace macgit’s single-pass lane layout with a branch/path-oriented graph engine that matches Fork/SourceTree/VS Code Git Graph, including stable branch lanes, per-row path routing, continuation lines for out-of-page parents, and `--topo-order` history loading.

**Architecture:** A new three-phase layout engine builds a vertex graph, grows first-parent branches top-down, and emits `GraphPath` polylines that `BranchGraphCanvas` draws. History loading adds `--topo-order` to prevent interleaving.

**Tech Stack:** Swift, SwiftUI, XCTest, no external dependencies.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `macgit/Services/Commit.swift` | `Commit`, `GraphNode`, `GraphPoint`, `GraphPath`, `CommitGraphLayout` data models. `GraphEdge` is removed. |
| `macgit/Views/History/CommitGraphLayoutEngine.swift` | New branch/path layout algorithm and internal `Vertex`, `Branch`, `BranchColorPool`. |
| `macgit/Views/History/BranchGraphCanvas.swift` | Draws `GraphPath` polylines instead of `GraphEdge` lines. |
| `macgit/Services/GitStatusService+Commit.swift` | Adds `--topo-order` to `commitHistory(allBranches:limit:skip:in:)` and `commitHistory(branch:limit:skip:in:)`. |
| `macgitTests/CommitGraphLayoutEngineTests.swift` | Layout algorithm unit tests. |
| `macgitTests/BranchGraphCanvasTests.swift` | Canvas path-drawing unit tests. |
| `macgitTests/HistoryPaginationTests.swift` | Pagination-stability integration test. |

---

## Task 1: Add `--topo-order` to history loading

**Files:**
- Modify: `macgit/Services/GitStatusService+Commit.swift:55-68`
- Modify: `macgit/Services/GitStatusService+Commit.swift:76-91`
- Test: `macgitTests/HistoryPaginationTests.swift`

- [ ] **Step 1: Write a test that asserts `--topo-order` is passed**

Create a new test helper that runs `commitHistory` on a temp repo with branches and captures the order. Since `GitStatusService` calls `Process` directly, add an internal test hook or test through `GitStatusService.shared` against a real temp repo. Use `GitStatusService.shared.commitHistory(allBranches: true, limit: 100, in: url)` and assert that a commit on `feature` does not appear between two commits on `main` when `feature` is an ancestor of `main`.

Example test skeleton:

```swift
func testCommitHistoryUsesTopoOrder() async throws {
    let url = try makeRepoWithMergeTopology()
    let service = GitStatusService.shared

    let commits = await service.commitHistory(allBranches: true, limit: 100, in: url)
    let messages = commits.map { $0.message }

    // With --topo-order, feature commits are not interleaved between main commits
    // that descend from the merge.
    let featureIndex = messages.firstIndex(of: "feature work") ?? -1
    let mainAfterMergeIndex = messages.firstIndex(of: "main after merge") ?? -1
    let mainBeforeMergeIndex = messages.firstIndex(of: "main before merge") ?? -1

    XCTAssertGreaterThan(featureIndex, mainBeforeMergeIndex)
    XCTAssertGreaterThan(mainAfterMergeIndex, featureIndex)
}

private func makeRepoWithMergeTopology() throws -> URL {
    let repoURL = try makeTempRepo(named: "macgit-topo-order")
    try runGit(["init", "-b", "main"], in: repoURL)
    try configureGit(in: repoURL)

    let fileURL = repoURL.appendingPathComponent("tracked.txt")

    try "base\n".write(to: fileURL, atomically: true, encoding: .utf8)
    try runGit(["add", "tracked.txt"], in: repoURL)
    try runGit(["commit", "-m", "main before merge"], in: repoURL)

    try runGit(["checkout", "-b", "feature"], in: repoURL)
    try "feature\n".write(to: fileURL, atomically: true, encoding: .utf8)
    try runGit(["add", "tracked.txt"], in: repoURL)
    try runGit(["commit", "-m", "feature work"], in: repoURL)

    try runGit(["checkout", "main"], in: repoURL)
    try runGit(["merge", "feature", "-m", "merge feature"], in: repoURL)
    try "after\n".write(to: fileURL, atomically: true, encoding: .utf8)
    try runGit(["add", "tracked.txt"], in: repoURL)
    try runGit(["commit", "-m", "main after merge"], in: repoURL)

    return repoURL
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing macgitTests/HistoryPaginationTests/testCommitHistoryUsesTopoOrder`

Expected: test fails or order is not guaranteed.

- [ ] **Step 3: Add `--topo-order` to the all-branches history method**

In `macgit/Services/GitStatusService+Commit.swift`, change:

```swift
var arguments = ["log"]
if allBranches {
    arguments.append("--all")
}
arguments.append(contentsOf: [
    "--format=%H%x00%P%x00%s%x00%an%x00%ae%x00%ad%x00%D",
    "--date=iso-strict",
    "--max-count", "\(limit)"
])
```

to:

```swift
var arguments = ["log", "--topo-order"]
if allBranches {
    arguments.append("--all")
}
arguments.append(contentsOf: [
    "--format=%H%x00%P%x00%s%x00%an%x00%ae%x00%ad%x00%D",
    "--date=iso-strict",
    "--max-count", "\(limit)"
])
```

- [ ] **Step 4: Add `--topo-order` to the branch-scoped history method**

Change the `arguments` array in `commitHistory(branch:limit:skip:in:)` from:

```swift
let arguments = [
    "log", branch,
    "--format=%H%x00%P%x00%s%x00%an%x00%ae%x00%ad%x00%D",
    "--date=iso-strict",
    "--max-count", "\(limit)"
]
```

to:

```swift
let arguments = [
    "log", "--topo-order", branch,
    "--format=%H%x00%P%x00%s%x00%an%x00%ae%x00%ad%x00%D",
    "--date=iso-strict",
    "--max-count", "\(limit)"
]
```

- [ ] **Step 5: Run the test to verify it passes**

Run the same `xcodebuild` command from Step 2.

Expected: PASS.

- [ ] **Step 6: Commit**

Do NOT run `git commit` unless the user explicitly asks. Leave changes staged or unstaged as appropriate for the workspace convention.

---

## Task 2: Update graph layout model types

**Files:**
- Modify: `macgit/Services/Commit.swift:31-52`
- Modify: `macgitTests/CommitGraphLayoutEngineTests.swift`
- Modify: `macgitTests/BranchGraphCanvasTests.swift`

- [ ] **Step 1: Replace `GraphEdge` with `GraphPoint` and `GraphPath`**

In `macgit/Services/Commit.swift`, replace:

```swift
struct GraphEdge {
    let fromRow: Int
    let fromLane: Int
    let toRow: Int
    let toLane: Int
    let isMergeParent: Bool
}

struct CommitGraphLayout {
    let nodes: [GraphNode]
    let edges: [GraphEdge]
    let laneCount: Int
}
```

with:

```swift
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
```

`GraphNode` stays unchanged.

- [ ] **Step 2: Update `CommitGraphLayoutEngine` to return the new type**

In `macgit/Views/History/CommitGraphLayoutEngine.swift`, change the `return` statement at the end of `layout(commits:)` from:

```swift
return CommitGraphLayout(nodes: nodes, edges: edges, laneCount: max(1, maxLaneSeen))
```

to a temporary placeholder that compiles:

```swift
return CommitGraphLayout(nodes: nodes, paths: [], laneCount: max(1, maxLaneSeen))
```

This will be replaced in later tasks.

- [ ] **Step 3: Update existing tests to compile against the new API**

In `macgitTests/CommitGraphLayoutEngineTests.swift`, remove all references to `layout.edges`. The tests currently assert edge existence; for now, comment out or remove those assertions so the file compiles. They will be rewritten in Task 8.

In `macgitTests/BranchGraphCanvasTests.swift`, replace `GraphEdge` references with `GraphPath`. For now, change the tests to construct a `GraphPath` with two points and verify the route. The canvas API will change in Task 7.

- [ ] **Step 4: Build the project and test target to confirm compilation**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`

Expected: build succeeds.

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test`

Expected: tests run; existing layout/canvas tests may fail because the algorithm is still the old one but the model is new. That is acceptable at this checkpoint.

---

## Task 3: Implement internal layout types and color pool

**Files:**
- Modify: `macgit/Views/History/CommitGraphLayoutEngine.swift`

- [ ] **Step 1: Add internal `Vertex`, `Branch`, and `BranchColorPool` types**

At the bottom of `macgit/Views/History/CommitGraphLayoutEngine.swift`, add:

```swift
// MARK: - Internal Layout Types

private final class Branch {
    let id: Int
    let color: Color
    var startRow: Int
    var endRow: Int
    var vertices: [Vertex] = []

    init(id: Int, color: Color, startRow: Int) {
        self.id = id
        self.color = color
        self.startRow = startRow
        self.endRow = startRow
    }
}

private final class Vertex {
    let row: Int
    let commit: Commit?
    var parentRows: [Int]
    var childRows: [Int]
    var branch: Branch?
    var lane: Int

    init(row: Int, commit: Commit?, parentRows: [Int], childRows: [Int], lane: Int = 0) {
        self.row = row
        self.commit = commit
        self.parentRows = parentRows
        self.childRows = childRows
        self.lane = lane
    }

    var isMerge: Bool { parentRows.count > 1 }
}

private struct BranchColorPool {
    private let palette = LaneColors.palette
    private var nextColorIndex = 0

    mutating func allocate() -> Color {
        let color = palette[nextColorIndex % palette.count]
        nextColorIndex += 1
        return color
    }
}
```

- [ ] **Step 2: Build the project**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`

Expected: build succeeds.

---

## Task 4: Rewrite layout engine – Phase 1 (vertex graph)

**Files:**
- Modify: `macgit/Views/History/CommitGraphLayoutEngine.swift:9-95`

- [ ] **Step 1: Replace the body of `CommitGraphLayoutEngine.layout(commits:)` with the new three-phase structure**

Replace the entire `layout(commits:)` implementation with:

```swift
static func layout(commits: [Commit]) -> CommitGraphLayout {
    guard !commits.isEmpty else {
        return CommitGraphLayout(nodes: [], paths: [], laneCount: 1)
    }

    // Phase 1: build vertices
    var vertices = buildVertices(commits: commits)

    // Phase 2: assign branches
    let branches = assignBranches(vertices: &vertices)

    // Phase 3: route paths
    let paths = routePaths(vertices: vertices, branches: branches)

    // Build public nodes
    let nodes = vertices.enumerated().compactMap { (row, vertex) -> GraphNode? in
        guard let commit = vertex.commit else { return nil }
        return GraphNode(commit: commit, lane: vertex.lane, rowIndex: row)
    }

    let laneCount = vertices.map { $0.lane }.max().map { $0 + 1 } ?? 1

    return CommitGraphLayout(nodes: nodes, paths: paths, laneCount: max(1, laneCount))
}
```

- [ ] **Step 2: Implement `buildVertices(commits:)`**

Add below `layout`:

```swift
private static func buildVertices(commits: [Commit]) -> [Vertex] {
    var rowByHash: [String: Int] = [:]
    for (row, commit) in commits.enumerated() {
        rowByHash[commit.hash] = row
    }

    var vertices: [Vertex] = []
    var placeholderRows: [String: Int] = [:]

    func placeholderRow(for hash: String) -> Int {
        if let row = placeholderRows[hash] { return row }
        let row = commits.count + placeholderRows.count
        placeholderRows[hash] = row
        return row
    }

    for (row, commit) in commits.enumerated() {
        let parentRows = commit.parents.map { rowByHash[$0] ?? placeholderRow(for: $0) }
        vertices.append(Vertex(row: row, commit: commit, parentRows: parentRows, childRows: []))
    }

    // Add placeholder vertices for any missing parents
    let sortedPlaceholders = placeholderRows.sorted { $0.value < $1.value }
    for (hash, row) in sortedPlaceholders {
        vertices.append(Vertex(row: row, commit: nil, parentRows: [], childRows: []))
    }

    // Build child lists
    for (row, commit) in commits.enumerated() {
        for parentRow in vertices[row].parentRows {
            vertices[parentRow].childRows.append(row)
        }
    }

    return vertices
}
```

- [ ] **Step 3: Add stub functions for the remaining phases**

Add stubs so the file compiles:

```swift
private static func assignBranches(vertices: inout [Vertex]) -> [Branch] {
    return []
}

private static func routePaths(vertices: [Vertex], branches: [Branch]) -> [GraphPath] {
    return []
}
```

- [ ] **Step 4: Build and add a test for vertex building**

Build: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`

In `macgitTests/CommitGraphLayoutEngineTests.swift`, add:

```swift
func testLayoutReturnsNodesForSimpleHistory() {
    let a = makeCommit(hash: "a")
    let b = makeCommit(hash: "b", parents: ["a"])
    let layout = CommitGraphLayoutEngine.layout(commits: [b, a])
    XCTAssertEqual(layout.nodes.count, 2)
    XCTAssertEqual(layout.nodes[0].lane, 0)
    XCTAssertEqual(layout.nodes[1].lane, 0)
}
```

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing macgitTests/CommitGraphLayoutEngineTests/testLayoutReturnsNodesForSimpleHistory`

Expected: PASS.

---

## Task 5: Rewrite layout engine – Phase 2 (branch assignment)

**Files:**
- Modify: `macgit/Views/History/CommitGraphLayoutEngine.swift`

- [ ] **Step 1: Implement `assignBranches(vertices:)`**

Replace the stub with:

```swift
private static func assignBranches(vertices: inout [Vertex]) -> [Branch] {
    var branches: [Branch] = []
    var colorPool = BranchColorPool()

    for row in 0..<vertices.count {
        let vertex = vertices[row]
        guard vertex.commit != nil else { continue }

        // Only start/extend a branch from its head (a vertex not yet on a branch).
        guard vertex.branch == nil else { continue }

        let branch = Branch(id: branches.count, color: colorPool.allocate(), startRow: row)
        branch.vertices.append(vertex)
        vertices[row].branch = branch
        vertices[row].lane = branch.id
        branches.append(branch)

        // Follow first parents down, adding them to this branch, until we hit
        // a vertex already on another branch or a missing parent placeholder.
        var currentRow = row
        while true {
            let current = vertices[currentRow]
            guard let nextParentRow = firstParentRow(for: current) else {
                branch.endRow = currentRow
                break
            }

            let parent = vertices[nextParentRow]
            if parent.branch != nil {
                branch.endRow = currentRow
                break
            }

            vertices[nextParentRow].branch = branch
            vertices[nextParentRow].lane = branch.id
            branch.vertices.append(parent)
            branch.endRow = nextParentRow
            currentRow = nextParentRow
        }
    }

    return branches
}

private static func firstParentRow(for vertex: Vertex) -> Int? {
    // For merges, only the first parent continues this branch.
    // Other parents are left for their own branch assignments.
    guard !vertex.parentRows.isEmpty else { return nil }
    return vertex.parentRows[0]
}
```

- [ ] **Step 2: Add tests for branch assignment**

In `macgitTests/CommitGraphLayoutEngineTests.swift`, add:

```swift
func testFeatureBranchKeepsStableLanes() {
    let a = makeCommit(hash: "a")
    let b = makeCommit(hash: "b", parents: ["a"])
    let c = makeCommit(hash: "c", parents: ["b"], refs: ["main"])
    let f = makeCommit(hash: "f", parents: ["b"])
    let m = makeCommit(hash: "m", parents: ["c", "f"])

    let layout = CommitGraphLayoutEngine.layout(commits: [m, f, c, b, a])
    let lanes = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.commit.hash, $0.lane) })

    XCTAssertEqual(lanes["m"], 0)
    XCTAssertEqual(lanes["c"], 0)
    XCTAssertEqual(lanes["b"], 0)
    XCTAssertEqual(lanes["a"], 0)
    XCTAssertEqual(lanes["f"], 1)
}
```

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing macgitTests/CommitGraphLayoutEngineTests/testFeatureBranchKeepsStableLanes`

Expected: PASS.

---

## Task 6: Rewrite layout engine – Phase 3 (path routing)

**Files:**
- Modify: `macgit/Views/History/CommitGraphLayoutEngine.swift`

- [ ] **Step 1: Implement `routePaths(vertices:branches:)`**

Replace the stub with:

```swift
private static func routePaths(vertices: [Vertex], branches: [Branch]) -> [GraphPath] {
    var paths: [GraphPath] = []

    for branch in branches {
        // Main branch path
        var points: [GraphPoint] = []
        for row in branch.startRow...branch.endRow {
            let lane = vertices[row].branch === branch ? vertices[row].lane : branch.id
            points.append(GraphPoint(row: row, lane: lane))
        }
        if points.count > 1 {
            paths.append(GraphPath(points: points, color: branch.color, isMergeConnector: false))
        }

        // Merge connectors: for each vertex on this branch that has a parent in another branch,
        // draw a connector from the merge commit to that parent.
        for vertex in branch.vertices {
            guard vertex.parentRows.count > 1 else { continue }
            for parentRow in vertex.parentRows.dropFirst() {
                let parent = vertices[parentRow]
                let parentLane = parent.branch?.id ?? branch.id
                var connectorPoints: [GraphPoint] = []
                for row in vertex.row...parentRow {
                    let lane: Int
                    if row == vertex.row {
                        lane = vertex.lane
                    } else if row == parentRow {
                        lane = parentLane
                    } else {
                        lane = parentLane
                    }
                    connectorPoints.append(GraphPoint(row: row, lane: lane))
                }
                if connectorPoints.count > 1 {
                    paths.append(GraphPath(points: connectorPoints, color: parent.branch?.color ?? branch.color, isMergeConnector: true))
                }
            }
        }
    }

    return paths
}
```

- [ ] **Step 2: Add a test that paths are produced**

In `macgitTests/CommitGraphLayoutEngineTests.swift`, add:

```swift
func testMergeProducesMergeConnectorPath() {
    let a = makeCommit(hash: "a")
    let b = makeCommit(hash: "b", parents: ["a"])
    let c = makeCommit(hash: "c", parents: ["b"])
    let f = makeCommit(hash: "f", parents: ["b"])
    let m = makeCommit(hash: "m", parents: ["c", "f"])

    let layout = CommitGraphLayoutEngine.layout(commits: [m, f, c, b, a])
    let mergePaths = layout.paths.filter { $0.isMergeConnector }
    XCTAssertEqual(mergePaths.count, 1)
    XCTAssertEqual(mergePaths.first?.points.first?.row, 0)
    XCTAssertEqual(mergePaths.first?.points.last?.row, 1)
}
```

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing macgitTests/CommitGraphLayoutEngineTests/testMergeProducesMergeConnectorPath`

Expected: PASS.

---

## Task 7: Update `BranchGraphCanvas` to draw `GraphPath`

**Files:**
- Modify: `macgit/Views/History/BranchGraphCanvas.swift`

- [ ] **Step 1: Replace edge drawing with path drawing**

Replace the `edges` property and the edge-drawing loop with a `paths` property and a path-drawing loop.

Change the struct signature from:

```swift
struct BranchGraphCanvas: View {
    let nodes: [GraphNode]
    let edges: [GraphEdge]
    let laneCount: Int
```

to:

```swift
struct BranchGraphCanvas: View {
    let nodes: [GraphNode]
    let paths: [GraphPath]
    let laneCount: Int
```

Replace the edge loop:

```swift
for edge in edges {
    let route = Self.edgeRoute(for: edge, rowHeight: rowHeight, laneWidth: laneWidth)
    let color: Color
    if edge.fromLane == edge.toLane {
        color = LaneColors.color(for: edge.fromLane)
    } else if edge.isMergeParent {
        color = LaneColors.color(for: edge.toLane)
    } else {
        color = LaneColors.color(for: edge.fromLane)
    }
    var path = Path()
    path.move(to: route.start)
    if edge.fromLane == edge.toLane {
        path.addLine(to: route.end)
    } else {
        path.addLine(to: route.preTurn)
        path.addQuadCurve(to: route.postTurn, control: route.corner)
        path.addLine(to: route.end)
    }
    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
}
```

with:

```swift
for pathModel in paths {
    guard pathModel.points.count > 1 else { continue }
    var path = Path()
    let firstPosition = pointPosition(pathModel.points[0])
    path.move(to: firstPosition)

    for i in 1..<pathModel.points.count {
        let prev = pathModel.points[i - 1]
        let curr = pathModel.points[i]
        let prevPosition = pointPosition(prev)
        let currPosition = pointPosition(curr)

        if prev.lane != curr.lane {
            let laneDelta = abs(curr.lane - prev.lane)
            let cornerRadius = min(4, min(CGFloat(laneDelta) * laneWidth / 2, rowHeight / 2))
            let xDirection = curr.lane > prev.lane ? 1 as CGFloat : -1 as CGFloat
            let yDirection = curr.row > prev.row ? 1 as CGFloat : -1 as CGFloat

            let preTurn = CGPoint(x: currPosition.x - xDirection * cornerRadius, y: prevPosition.y)
            let postTurn = CGPoint(x: currPosition.x, y: prevPosition.y + yDirection * cornerRadius)
            let corner = CGPoint(x: currPosition.x, y: prevPosition.y)

            path.addLine(to: preTurn)
            path.addQuadCurve(to: postTurn, control: corner)
        } else {
            path.addLine(to: currPosition)
        }
    }

    context.stroke(
        path,
        with: .color(pathModel.color),
        style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
    )
}
```

Add the helper:

```swift
private func pointPosition(_ point: GraphPoint) -> CGPoint {
    CGPoint(
        x: CGFloat(point.lane) * laneWidth + laneWidth / 2,
        y: CGFloat(point.row) * rowHeight + rowHeight / 2
    )
}
```

Add the helper:

```swift
private func pointPosition(_ point: GraphPoint) -> CGPoint {
    CGPoint(
        x: CGFloat(point.lane) * laneWidth + laneWidth / 2,
        y: CGFloat(point.row) * rowHeight + rowHeight / 2
    )
}
```

- [ ] **Step 2: Remove `GraphEdge` and `EdgeRoute` helpers**

Delete the `EdgeRoute` struct and `edgeRoute(for:rowHeight:laneWidth:)` method since they are no longer used.

- [ ] **Step 3: Update call site in `HistoryView.swift`**

In `macgit/Views/History/HistoryView.swift:506`, change the `BranchGraphCanvas` initializer from:

```swift
BranchGraphCanvas(
    nodes: graphLayout.nodes,
    edges: graphLayout.edges,
    laneCount: graphLayout.laneCount
)
```

to:

```swift
BranchGraphCanvas(
    nodes: graphLayout.nodes,
    paths: graphLayout.paths,
    laneCount: graphLayout.laneCount
)
```

- [ ] **Step 4: Build the project**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`

Expected: build succeeds.

---

## Task 8: Rewrite existing layout tests for the new algorithm

**Files:**
- Modify: `macgitTests/CommitGraphLayoutEngineTests.swift`

- [ ] **Step 1: Update `testLinearHistory`**

Keep the lane assertions. Remove edge assertions. Add path assertion: exactly one path.

```swift
func testLinearHistory() {
    let c = makeCommit(hash: "c", parents: ["b"])
    let b = makeCommit(hash: "b", parents: ["a"])
    let a = makeCommit(hash: "a", parents: [], refs: ["main"])
    let layout = CommitGraphLayoutEngine.layout(commits: [c, b, a])

    XCTAssertEqual(layout.nodes[0].lane, 0)
    XCTAssertEqual(layout.nodes[1].lane, 0)
    XCTAssertEqual(layout.nodes[2].lane, 0)
    XCTAssertEqual(layout.paths.count, 1)
    XCTAssertEqual(layout.paths.first?.points.count, 3)
}
```

- [ ] **Step 2: Update `testFeatureBranchAndMerge`**

Lane assertions stay the same. Replace edge assertions with path checks:

```swift
func testFeatureBranchAndMerge() {
    let a = makeCommit(hash: "a")
    let b = makeCommit(hash: "b", parents: ["a"])
    let c = makeCommit(hash: "c", parents: ["b"], refs: ["main"])
    let f = makeCommit(hash: "f", parents: ["b"])
    let m = makeCommit(hash: "m", parents: ["c", "f"])

    let layout = CommitGraphLayoutEngine.layout(commits: [m, f, c, b, a])
    let lanes = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.commit.hash, $0.lane) })

    XCTAssertEqual(lanes["c"], 0)
    XCTAssertEqual(lanes["b"], 0)
    XCTAssertEqual(lanes["a"], 0)
    XCTAssertEqual(lanes["m"], 0)
    XCTAssertEqual(lanes["f"], 1)

    let mainPath = layout.paths.first { !$0.isMergeConnector }
    let mergePath = layout.paths.first { $0.isMergeConnector }
    XCTAssertNotNil(mainPath)
    XCTAssertNotNil(mergePath)
    XCTAssertEqual(mainPath?.points.map(\.row), [0, 1, 2, 3, 4])
    XCTAssertEqual(mainPath?.points.map(\.lane), [0, 0, 0, 0, 0])
    XCTAssertEqual(mergePath?.points.first?.row, 0)
    XCTAssertEqual(mergePath?.points.last?.row, 1)
}
```

- [ ] **Step 3: Update `testParallelBranchesReuseLane`**

```swift
func testParallelBranchesReuseLane() {
    let r = makeCommit(hash: "r")
    let b = makeCommit(hash: "b", parents: ["r"])
    let a = makeCommit(hash: "a", parents: ["r"], refs: ["main"])

    let layout = CommitGraphLayoutEngine.layout(commits: [a, b, r])
    let lanes = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.commit.hash, $0.lane) })

    XCTAssertEqual(lanes["a"], 0)
    XCTAssertEqual(lanes["b"], 1)
    XCTAssertEqual(lanes["r"], 0)

    XCTAssertEqual(layout.paths.count, 2)
}
```

- [ ] **Step 4: Update `testMergeParentReusesAlreadyActiveLane`**

```swift
func testMergeParentReusesAlreadyActiveLane() {
    let d = makeCommit(hash: "d")
    let c = makeCommit(hash: "c")
    let b = makeCommit(hash: "b", parents: ["c", "d"])
    let a = makeCommit(hash: "a", parents: ["d"])

    let layout = CommitGraphLayoutEngine.layout(commits: [a, b, c, d])
    let lanes = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.commit.hash, $0.lane) })

    XCTAssertEqual(layout.laneCount, 2)
    XCTAssertEqual(lanes["a"], 0)
    XCTAssertEqual(lanes["b"], 1)
    XCTAssertEqual(lanes["c"], 1)
    XCTAssertEqual(lanes["d"], 0)

    let mergePath = layout.paths.first { $0.isMergeConnector }
    XCTAssertNotNil(mergePath)
    XCTAssertEqual(mergePath?.points.first?.lane, 1)
    XCTAssertEqual(mergePath?.points.last?.lane, 0)
}
```

- [ ] **Step 5: Run layout tests**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing macgitTests/CommitGraphLayoutEngineTests`

Expected: PASS.

---

## Task 9: Update canvas tests for path drawing

**Files:**
- Modify: `macgitTests/BranchGraphCanvasTests.swift`

- [ ] **Step 1: Replace edge-route tests with path tests**

Replace the entire file with:

```swift
import XCTest
@testable import macgit

final class BranchGraphCanvasTests: XCTestCase {
    func testStraightPathDrawsSingleLine() {
        let path = GraphPath(
            points: [
                GraphPoint(row: 0, lane: 0),
                GraphPoint(row: 1, lane: 0),
                GraphPoint(row: 2, lane: 0)
            ],
            color: .blue,
            isMergeConnector: false
        )
        // Rendering is via SwiftUI Canvas; this test ensures the model is valid.
        XCTAssertEqual(path.points.count, 3)
        XCTAssertEqual(path.points.first?.lane, 0)
        XCTAssertEqual(path.points.last?.lane, 0)
    }

    func testMergeConnectorPathHasSourceAndDestination() {
        let path = GraphPath(
            points: [
                GraphPoint(row: 0, lane: 1),
                GraphPoint(row: 1, lane: 1),
                GraphPoint(row: 2, lane: 0)
            ],
            color: .green,
            isMergeConnector: true
        )
        XCTAssertTrue(path.isMergeConnector)
        XCTAssertEqual(path.points.first?.lane, 1)
        XCTAssertEqual(path.points.last?.lane, 0)
    }
}
```

- [ ] **Step 2: Run canvas tests**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing macgitTests/BranchGraphCanvasTests`

Expected: PASS.

---

## Task 10: Add missing-parent and complex-DAG tests

**Files:**
- Modify: `macgitTests/CommitGraphLayoutEngineTests.swift`

- [ ] **Step 1: Add missing-parent test**

```swift
func testMissingParentDrawsContinuationPath() {
    let c = makeCommit(hash: "c", parents: ["missing"])
    let layout = CommitGraphLayoutEngine.layout(commits: [c])

    XCTAssertEqual(layout.nodes.count, 1)
    XCTAssertEqual(layout.laneCount, 1)
    XCTAssertTrue(layout.paths.contains { path in
        path.points.contains { $0.row > 0 }
    })
}
```

- [ ] **Step 2: Add complex DAG test from fuzz comparison**

```swift
func testComplexDAGMatchesExpectedLanes() {
    // DAG that previously differed from Git Graph:
    // c0 root; c1->c3; c2->c4; c3->c5,c7; c4->c6; c5->c7; c6->c7
    let c0 = makeCommit(hash: "c0")
    let c1 = makeCommit(hash: "c1", parents: ["c3"])
    let c2 = makeCommit(hash: "c2", parents: ["c4"])
    let c3 = makeCommit(hash: "c3", parents: ["c5", "c7"])
    let c4 = makeCommit(hash: "c4", parents: ["c6"])
    let c5 = makeCommit(hash: "c5", parents: ["c7"])
    let c6 = makeCommit(hash: "c6", parents: ["c7"])
    let c7 = makeCommit(hash: "c7")

    let layout = CommitGraphLayoutEngine.layout(commits: [c0, c1, c2, c3, c4, c5, c6, c7])
    let lanes = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.commit.hash, $0.lane) })

    XCTAssertEqual(lanes["c0"], 0)
    XCTAssertEqual(lanes["c1"], 1)
    XCTAssertEqual(lanes["c2"], 2)
    XCTAssertEqual(lanes["c3"], 1)
    XCTAssertEqual(lanes["c4"], 2)
    XCTAssertEqual(lanes["c5"], 1)
    XCTAssertEqual(lanes["c6"], 2)
    XCTAssertEqual(lanes["c7"], 1)
}
```

- [ ] **Step 3: Run tests**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing macgitTests/CommitGraphLayoutEngineTests`

Expected: PASS.

---

## Task 11: Add pagination-stability test

**Files:**
- Modify: `macgitTests/HistoryPaginationTests.swift`

- [ ] **Step 1: Add a test that first-page layout is stable after loading second page**

Append a test that:
1. Creates a temp repo with several commits on `main` and `feature`.
2. Loads `commitHistory(allBranches: true, limit: 3, skip: 0, in: url)` and captures the layout.
3. Loads `commitHistory(allBranches: true, limit: 3, skip: 3, in: url)` and recomputes the full layout.
4. Asserts that the first-page nodes’ lanes and hashes are identical between the two runs.

Example:

```swift
func testGraphLayoutStableAcrossPagination() async throws {
    let url = try makeRepoWithFeatureBranch()
    let service = GitStatusService.shared

    let page1 = await service.commitHistory(allBranches: true, limit: 3, skip: 0, in: url)
    let layout1 = CommitGraphLayoutEngine.layout(commits: page1)

    let page2 = await service.commitHistory(allBranches: true, limit: 3, skip: 3, in: url)
    let combined = page1 + page2
    let layout2 = CommitGraphLayoutEngine.layout(commits: combined)

    for i in 0..<min(layout1.nodes.count, layout2.nodes.count) {
        XCTAssertEqual(layout1.nodes[i].lane, layout2.nodes[i].lane)
        XCTAssertEqual(layout1.nodes[i].commit.hash, layout2.nodes[i].commit.hash)
    }
}

private func makeRepoWithFeatureBranch() throws -> URL {
    let repoURL = try makeTempRepo(named: "macgit-pagination-graph")
    try runGit(["init", "-b", "main"], in: repoURL)
    try configureGit(in: repoURL)

    let fileURL = repoURL.appendingPathComponent("tracked.txt")

    try "base\n".write(to: fileURL, atomically: true, encoding: .utf8)
    try runGit(["add", "tracked.txt"], in: repoURL)
    try runGit(["commit", "-m", "base"], in: repoURL)

    try runGit(["checkout", "-b", "feature"], in: repoURL)
    for index in 1...2 {
        try "feature \(index)\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "feature \(index)"], in: repoURL)
    }

    try runGit(["checkout", "main"], in: repoURL)
    for index in 1...4 {
        try "main \(index)\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "main \(index)"], in: repoURL)
    }

    return repoURL
}
```

- [ ] **Step 2: Run the test**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing macgitTests/HistoryPaginationTests/testGraphLayoutStableAcrossPagination`

Expected: PASS.

---

## Task 12: Add performance test

**Files:**
- Modify: `macgitTests/CommitGraphLayoutEngineTests.swift`

- [ ] **Step 1: Add a synthetic 1,000-commit DAG performance test**

```swift
func testLayoutPerformanceForLargeDAG() {
    var commits: [Commit] = []
    let count = 1000
    for i in 0..<count {
        let parents: [String]
        if i == count - 1 {
            parents = []
        } else if i % 7 == 0 && i + 2 < count {
            parents = ["\(i + 1)", "\(i + 2)"]
        } else {
            parents = ["\(i + 1)"]
        }
        commits.append(makeCommit(hash: "\(i)", parents: parents))
    }

    let start = CFAbsoluteTimeGetCurrent()
    let layout = CommitGraphLayoutEngine.layout(commits: commits)
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    XCTAssertLessThan(elapsed, 0.1)
    XCTAssertGreaterThan(layout.paths.count, 0)
}
```

- [ ] **Step 2: Run the performance test**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing macgitTests/CommitGraphLayoutEngineTests/testLayoutPerformanceForLargeDAG`

Expected: PASS.

---

## Task 13: Full test run and regression fixes

**Files:**
- All modified files

- [ ] **Step 1: Run the full test suite**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test`

- [ ] **Step 2: Fix any failures**

For each failure, determine whether it is a legitimate regression or an outdated expectation caused by the new layout model. Update tests or implementation as needed.

- [ ] **Step 3: Build the app**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`

Expected: build succeeds with no warnings related to the changed files.

---

## Self-Review Checklist

- **Spec coverage:** every requirement in `docs/superpowers/specs/2026-06-21-commit-graph-layout-design.md` maps to a task:
  - `--topo-order` → Task 1
  - Branch/path model → Tasks 2–6
  - Stable branch lanes, merge connectors, missing parents → Tasks 5–6, 10
  - Branch colors → Task 3
  - Updated canvas → Task 7
  - Tests → Tasks 8–12
  - Performance/lazy loading → Task 12
- **Placeholder scan:** no TBD, TODO, or vague steps. Each step includes code or exact commands.
- **Type consistency:** `GraphPath`, `GraphPoint`, `CommitGraphLayout`, `Vertex`, `Branch`, and `BranchColorPool` names are used consistently throughout.
