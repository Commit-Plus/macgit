# Sourcegit-Based Commit Graph Drawing Rewrite — Design Spec

## Background

The current `CommitGraphLayoutEngine` uses a first-parent-chain branch assignment that produces incorrect lane allocation for non-trivial DAGs: branches zigzag, merge connectors are drawn as straight polylines, and there is no visual distinction between the current branch and other branches when viewing all branches.

We will rewrite the graph generation and rendering to follow the algorithm and drawing style used by [sourcegit](https://github.com/sourcegit-scm/sourcegit) (`Models/CommitGraph.cs` and `Views/CommitGraph.cs`). This gives us:

- Correct lane assignment for complex DAGs, merges, and remote branches.
- Smooth quadratic/cubic Bézier curves for branch lines.
- Explicit merge links from the merge commit to the merged branch.
- Distinct dot styles for normal commits, HEAD, and merge commits.
- Highlighting modes: all branches in color, or only the current branch in color with everything else grayed out.

## Goals

- Port sourcegit's commit-graph model and generation algorithm to Swift.
- Port sourcegit's `CommitGraph` control rendering to a SwiftUI `Canvas`.
- Support both "All Branches" (including remotes) and "Current Branch" views.
- Preserve the existing lazy-loading behavior: graph is regenerated for the currently loaded commit slice.
- Maintain existing integration with `HistoryView`, `CommitRowView`, and `BranchFilterBar`.

## Non-goals

- User-configurable color palettes in this iteration. We use a fixed 10-color palette matching sourcegit's defaults.
- New history data fetching. We keep the existing `git log --topo-order --all` parsing.
- Persisting graph layout across app launches.

## Reference

- `src/Models/CommitGraph.cs` in sourcegit at commit `622315378bffcfdd55a213eb64135176a27b5ec1`.
- `src/Views/CommitGraph.cs` in sourcegit at the same commit.

## Algorithm

### Inputs

- `commits: [Commit]` — commits in reverse chronological (newest-first) topological order.
- `highlighting: CommitGraphHighlighting` — `.all` or `.currentBranchOnly`.
- `headHash: String?` — hash of the commit currently checked out (`HEAD`).

### Pre-processing

1. Build `rowByHash: [String: Int]`.
2. Build `merged: Set<String>` — all commits on the current branch:
   - Start with `headHash` if present.
   - Repeatedly add each commit's parents using `rowByHash` until no new parents are found.

### Per-commit loop

For each commit (top to bottom):

1. **Advance Y**: `offsetY += unitHeight`.
2. **Find active paths that link here**: iterate `unsolved` paths.
   - If `path.next == commit.hash`:
     - First match becomes `major` and continues to the commit's first parent.
     - Later matches end at this commit (they merge into `major`).
   - Otherwise the path simply passes through this row.
3. **Remove ended paths** from `unsolved` and recycle their color indices.
4. **Determine `isHighlighted`**:
   - `.all` → always `true`.
   - `.currentBranchOnly` → `true` if the commit is in `merged`.
5. **Create or continue a path**:
   - If `major` is `nil`, this commit is a new branch head. Start a new path to its first parent (if any).
   - If `major` exists and becomes highlighted when it wasn't before, split the path (sourcegit's `Highlight()`).
6. **Place the dot** at the major path's X position (or a fallback X for isolated commits). Dot type:
   - `.head` if the commit's refs contain `HEAD ->` or `HEAD`.
   - `.merge` if `parents.count > 1`.
   - `.default` otherwise.
7. **Handle merge parents** (`parents[1...]`):
   - Find an unsolved path waiting for that parent hash.
   - If found, add a `GraphLink` from the dot to the path and highlight if needed.
   - If not found, start a new path upward to that parent.
8. **Record metadata**: color index, highlight state, and left margin for the commit.

### Post-processing

For any path still in `unsolved` after the loop, end it at the bottom of the loaded slice:

```
endY = (commits.count - 0.5) * unitHeight
```

This naturally supports lazy loading: paths that continue beyond the loaded range simply trail off at the bottom and are redrawn when more commits are loaded.

### Internal helpers

- `PathHelper` (class) — tracks `next` hash, last X/Y, the `GraphPath` being built, and highlight state. Provides `pass`, `goto`, `end`, and `highlight`.
- `ColorPicker` — round-robin allocation of color indices with recycling when paths end.

Optimization: use a `[String: PathHelper]` dictionary for parent lookups instead of linear search.

## Data Model

```swift
struct CommitGraphModel {
    let paths: [GraphPath]
    let links: [GraphLink]
    let dots: [GraphDot]
    let laneCount: Int
    let commitMetadata: [String: GraphCommitMetadata]
}

struct GraphPath {
    let points: [CGPoint]
    let colorIndex: Int
    let isHighlighted: Bool
}

struct GraphLink {
    let start: CGPoint
    let control: CGPoint
    let end: CGPoint
    let colorIndex: Int
    let isHighlighted: Bool
}

enum GraphDotType {
    case `default`
    case head
    case merge
}

struct GraphDot {
    let center: CGPoint
    let type: GraphDotType
    let colorIndex: Int
    let isHighlighted: Bool
}

struct CommitGraphLayout {
    let startY: Double
    let clipWidth: Double
    let rowHeight: Double
}

enum CommitGraphHighlighting {
    case all
    case currentBranchOnly
}

struct GraphCommitMetadata {
    let colorIndex: Int
    let isHighlighted: Bool
    let leftMargin: Double
}
```

Coordinates are stored in sourcegit graph units (`unitWidth = 12`, `unitHeight = 1`) and scaled to SwiftUI points at render time.

## Rendering

`BranchGraphCanvas` becomes a SwiftUI `Canvas` port of sourcegit's `Views/CommitGraph`.

Constants:

- `unitWidth = 12` (sourcegit)
- `unitHeight = 1` (sourcegit)
- `rowHeight = 24` (macgit)
- `laneWidth = 14` (macgit)
- Pen thickness `2.2` (matching current macgit lines)

Drawing order:

1. **Clip and translate** to the visible viewport (`startY` to `startY + clipHeight + 28`).
2. **Draw paths** (`GraphPath`):
   - Same X → straight line.
   - X increasing → quadratic Bézier to the corner.
   - X decreasing and not the last segment → cubic Bézier through the mid Y.
   - X decreasing and last segment → quadratic Bézier.
   - Use the path's palette color if `isHighlighted`, otherwise a gray pen at 0.4 opacity.
3. **Draw links** (`GraphLink`) as quadratic Béziers.
4. **Draw dots** (`GraphDot`):
   - `.default` — filled circle with white border.
   - `.head` — outer ring filled with background color + inner solid dot.
   - `.merge` — hollow circle with a plus sign.
   - Grayed out if not highlighted.

## Integration with HistoryView

1. `showAllBranches` maps to highlighting:
   - `true` → `.all`
   - `false` → `.currentBranchOnly`
2. Resolve `headHash`:
   - Prefer extracting it from the refs of the loaded commits (`HEAD -> main`).
   - Fall back to `GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)` on first load.
3. Replace:
   ```swift
   graphLayout = CommitGraphLayoutEngine.layout(commits: commits)
   ```
   with:
   ```swift
   graphLayout = CommitGraphGenerator.generate(
       commits: commits,
       highlighting: highlighting,
       headHash: headHash
   )
   ```
4. `CommitRowView` continues to receive a `GraphNode`-like binding; the new generator returns nodes positioned at the dot center.
5. Lazy loading behavior is unchanged: when the user scrolls to the bottom and more commits load, the graph is regenerated for the full loaded set.

## Current Branch & Remote Branches

- **Current branch**: commits reachable from `headHash` are marked as `merged` and highlighted when `.currentBranchOnly` is selected.
- **Remote branches**: included automatically because `commitHistory(allBranches:)` uses `--all`; remote refs appear in `commit.refs` (e.g., `origin/main`) and are treated as ordinary branch heads.
- **Detached HEAD**: if refs contain `HEAD` without `HEAD ->`, that commit is treated as head and drawn with the `.head` dot.

## Files Affected

- `macgit/Views/History/CommitGraphTypes.swift` — replace types with sourcegit-aligned model.
- `macgit/Views/History/CommitGraphLayoutEngine.swift` — full rewrite as `CommitGraphGenerator`.
- `macgit/Views/History/BranchGraphCanvas.swift` — full rewrite for Bézier paths, links, and dots.
- `macgit/Views/History/HistoryView.swift` — pass highlighting mode and head hash.
- `macgitTests/CommitGraphLayoutEngineTests.swift` → `macgitTests/CommitGraphGeneratorTests.swift`.
- `macgitTests/BranchGraphCanvasTests.swift` — update rendering tests.

## Testing

### `CommitGraphGeneratorTests`

- Linear history: single path, lane 0.
- Feature branch + merge: main stays lane 0, feature lane 1, merge link exists.
- Octopus merge: correct lane count and merge links.
- Missing parent / lazy-loading boundary: path continues to bottom.
- `.all` highlighting: every path/link/dot highlighted.
- `.currentBranchOnly` highlighting: only current-branch elements highlighted.
- Remote branch head: creates a new branch path.
- Complex DAG: deterministic lane assignment.

### `BranchGraphCanvasTests`

- Straight vertical path bounds.
- Lane-changing path with quadratic/cubic curves.
- Single-point path returns empty path.
- Merge link quadratic Bézier bounds.
- Dot path bounds for default/head/merge.

### `HistoryViewTests`

- Switching `showAllBranches` changes the generated model's highlighting mode.

## Performance

- Generation is O(n × activePaths); with the parent-lookup dictionary optimization it's near-linear for typical repos.
- 1,000+ commits run well under a millisecond in Swift.
- Graph generation runs off the main actor; only the resulting model is assigned on `@MainActor`.
- No persistence: layout is recomputed on every load/filter/page change, same as today.

## Notes

- Because commits are value types in macgit, graph metadata (`colorIndex`, `isHighlighted`, `leftMargin`) is returned in `CommitGraphModel.commitMetadata` rather than mutating `Commit` directly.
- The existing `%H%x00%P%x00%s%x00%an%x00%ae%x00%ad%x00%D` git log format already provides parents and refs; no parser changes are needed.
