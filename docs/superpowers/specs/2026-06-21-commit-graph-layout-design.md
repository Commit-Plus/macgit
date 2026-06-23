# Commit Graph Layout Rewrite

## Status

Design approved. Awaiting implementation plan.

## Problem

The current history graph in macgit is drawn by a single-pass `activeLanes` algorithm in `CommitGraphLayoutEngine.swift`. It is compact and fast, but it produces a different visual feel from tools like Fork, SourceTree, and VS Code Git Graph:

- Branch lines collapse into the leftmost lane too aggressively, making unrelated branch heads share a column.
- Long edges are drawn as single straight lines rather than row-by-row branch paths, so crossings and overlaps are not resolved.
- Parents outside the loaded page are silently dropped, so branch lines end abruptly.
- Colors are tied to lane number, not branch identity, so a branch can change color as the layout shifts.

Additionally, history is loaded with plain `git log`, which can interleave commits from parallel branches and make the graph look wobbly.

## Goal

Rewrite the layout engine so the history graph behaves like mainstream GUI Git clients:

- Branch heads each get a stable column.
- First-parent chains stay in one column.
- Merge parents branch in cleanly from their own columns.
- Lines continue for parents beyond the loaded page.
- Branch colors are stable per branch.
- History ordering avoids interleaving (`--topo-order`).
- Performance stays acceptable for repos with thousands of commits and lazy-loaded pages.

## Scope

In scope:

- Rewrite `CommitGraphLayoutEngine.layout(commits:)` to use a branch/path model.
- Update `CommitGraphLayout`, `GraphNode`, and drawing code in `BranchGraphCanvas`.
- Add `--topo-order` to `commitHistory` in `GitStatusService+Commit.swift`.
- Unit tests covering simple and complex DAGs, missing parents, pagination stability, and performance.

Out of scope (for this change):

- Full visual customization of colors, lane width, or dot shapes.
- Virtualizing graph rendering to only visible rows.
- Interacting with the graph (clicking lines, hovering branches).

## Architecture

The public entry point stays the same:

```swift
CommitGraphLayoutEngine.layout(commits: [Commit]) -> CommitGraphLayout
```

Internally the engine now works in three phases:

1. **Build vertices.** Each commit becomes a `GraphVertex` with parent/child row indices. Out-of-page parents become placeholder vertices.
2. **Grow branches top-down.** A branch is a first-parent chain (or merge-parent continuation). Each new branch gets a color and a lane. Walk from a vertex down through unprocessed parents, assigning each to the branch, until reaching a vertex already on a branch or a missing parent.
3. **Route paths.** Each branch emits a `GraphPath` — a top-to-bottom list of points with rounded corners where the lane changes. `BranchGraphCanvas` draws the paths, then draws commit dots on top.

## Components

### GraphVertex

```swift
struct GraphVertex {
    let row: Int
    let commit: Commit?      // nil for out-of-page parent placeholders
    let parentRows: [Int]    // -1 for missing/out-of-page parents
    let childRows: [Int]
    var branch: GraphBranch?
    var lane: Int
}
```

### GraphBranch

```swift
final class GraphBranch {
    let id: Int
    let color: Color
    var startRow: Int
    var endRow: Int
    var points: [GraphPoint] = []
}
```

### GraphPoint

```swift
struct GraphPoint: Equatable {
    let row: Int
    let lane: Int
}
```

### GraphPath

```swift
struct GraphPath {
    let branch: GraphBranch
    let points: [GraphPoint]
    let isMergeConnector: Bool
}
```

### CommitGraphLayout

```swift
struct CommitGraphLayout {
    let nodes: [GraphNode]
    let paths: [GraphPath]
    let laneCount: Int
}
```

`GraphEdge` is removed; `GraphNode` keeps its lane from the assigned branch.

### BranchColorPool

A small color allocator that reuses colors once a branch ends, cycling through the existing `LaneColors.palette`.

## Data Flow

1. `HistoryView.loadHistory(...)` calls `GitStatusService.shared.commitHistory(...)`.
2. After commits are fetched/extended, it calls `CommitGraphLayoutEngine.layout(commits:)`.
3. The engine builds vertices, assigns branches, routes paths, and returns `CommitGraphLayout`.
4. `BranchGraphCanvas` receives `nodes` and `paths` and draws each path as a polyline with rounded corners at lane changes, then draws dots on top.

## Algorithm Details

### Phase 1: Vertex graph

- Create a lookup `hash -> row`.
- For each commit, store parent row indices. A parent that is not in the lookup becomes a placeholder vertex at `row = commits.count` (just below the last loaded row); the child stores the placeholder's real row index.
- Collect child indices by walking parents.

### Phase 2: Branch assignment

For each vertex `v` from top row to bottom row:

- If `v.branch == nil`, create a new `GraphBranch` with the next available color. Set `v.branch` and `v.lane`.
- Starting from `v`, walk down through the next unprocessed parent:
  - Add the current vertex to the branch.
  - If the parent is already on a branch, or is a placeholder, end this branch after drawing the connection.
  - If the parent is not on a branch, add it to the same branch with the same lane and continue.
  - If `v` is a merge, only the first parent follows the main branch; remaining parents are left unprocessed and will spawn their own branches when the loop reaches them.

### Phase 3: Path routing

For each branch:

- Generate one `GraphPoint` per row from `startRow` to `endRow`.
- If the branch connects to a merge parent that sits in a different lane, insert a rounded corner near the merge commit (the source of the connector).
- If a first-parent chain changes lane at a convergence, insert a rounded corner near the destination commit.
- If the branch connects to a placeholder parent below the last commit, extend the last point to the placeholder row so the line continues downward.

### `--topo-order`

Add `--topo-order` to the `git log` arguments in `GitStatusService+Commit.swift`. This prevents interleaving of parallel history and matches the visual expectations of the new layout.

## Edge Cases

- **Empty history:** return `laneCount == 1`, empty nodes and paths.
- **Single commit:** one node at lane 0, no paths.
- **Unrelated roots:** each root with no children in the current view becomes a branch head and gets its own lane.
- **Octopus merges:** each parent beyond the first spawns its own `GraphPath`.
- **Pagination:** layout is recomputed for the full loaded set on each append. The deterministic algorithm keeps the top portion visually stable.
- **Missing parents:** placeholder vertices ensure lines continue past the loaded page.

## Performance

Targets:

- Layout of 1,000 commits < 16 ms on a modern Mac.
- Layout of 5,000 commits < 100 ms.

Efficiency notes:

- Vertex building is O(n).
- Branch assignment visits each vertex once per unprocessed parent: O(n + total parent links).
- Total path points are O(n × average branch density); typical repos are O(n).
- Use `Int` arrays for parent/child indices instead of dictionaries in hot loops.
- Pre-allocate `GraphPath.points` arrays with known capacity.

Lazy loading:

- Keep the existing `historyPageSize` + `loadOlderHistoryIfNeeded` pagination.
- Do not virtualize graph rendering to visible rows in this change; `Canvas` clips to bounds and `LazyVStack` keeps offscreen rows lazy.

## Testing

1. **Layout engine unit tests** (`CommitGraphLayoutEngineTests.swift`):
   - Linear history.
   - Simple merge with first-parent straight line.
   - Parallel branches keeping stable lanes.
   - Merge parent reusing an active lane.
   - Missing parent continuation path.
   - Complex DAGs from fuzz comparison.

2. **Canvas unit tests** (`BranchGraphCanvasTests.swift`):
   - Straight path draws a single line.
   - Merge connector rounds near source.
   - Lane change rounds at the correct row.

3. **Pagination integration test** (`HistoryPaginationTests.swift`):
   - Load first page, capture layout, load second page, assert first-page layout is unchanged.

4. **Performance test**:
   - Generate a 1,000-commit synthetic DAG and assert layout completes under a time threshold.

## Migration

- `GraphEdge` is removed from the public layout output. Any code depending on it must be updated; in the current codebase only `BranchGraphCanvas` consumes edges.
- `GraphNode` remains but its lane now comes from the assigned branch rather than the old active-lane sweep.

## Risks

- The new algorithm may produce more lanes (wider graphs) on repos with many independent branches. This is expected and matches other tools.
- Path routing complexity could introduce visual glitches on unusual merge topologies; fuzz tests mitigate this.
- `--topo-order` changes the order of commits in the history list. This matches Git Graph’s default behavior but is a user-visible change.
