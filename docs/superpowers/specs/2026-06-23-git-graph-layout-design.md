# Git Graph Layout Engine Rewrite — Design Spec

## Background

The current `CommitGraphLayoutEngine` uses a simple first-parent-chain branch assignment. It allocates a new lane for every unclaimed commit and recently regressed so that main branch lines zigzag through interleaved rows belonging to other branches.

We will port the layout algorithm from `gleisbau`, the rendering library behind [`git-graph`](https://github.com/git-bahn/git-graph) and [`gleisbau`](https://github.com/git-bahn/gleisbau). This produces the clean, GitFlow-aware graphs shown in the user screenshots.

## Goals

- Render GitFlow-style graphs with `master`/`main`/`develop` kept straight and supporting branches (`feature/*`, `release/*`, `hotfix/*`) placed predictably.
- Derive visual branches from real git refs, remote refs, tags, and merge commit summaries.
- Remove commits that are not on any visual branch, matching `gleisbau`.
- Compute connector bend points (`deviate_index`) so merges and forks do not cross other commits.
- Preserve SwiftUI Canvas rendering; reuse the existing `BranchGraphCanvas` path/drawing code where possible.

## Non-goals

- User-configurable branching models in this iteration. We use a fixed GitFlow-flavored default.
- Terminal/ASCII rendering. We only need the layout algorithm and the SVG-style connector logic.

## Algorithm

### Phase 1 — Build commit graph

From `[Commit]`:

- Map `hash -> row`.
- Build `children: [String]` reverse map from `parents`.
- Mark `isMerge = parents.count > 1`.

### Phase 2 — Extract branches

Collect branches from these sources, each becoming a `BranchInfo`:

1. **Local branches** (`refs/heads/*`).
2. **Remote branches** (`refs/remotes/origin/*`).
3. **Tags** (`refs/tags/*`).
4. **Merge-summary branches**: parse merge commit messages for patterns like `Merge branch 'feature/x'`, `Merge pull request #1 from ...`, `Merged in feature/x (pull request #1)`.

Each branch stores:

- `name`
- `targetHash` / `targetRow` (tip of the branch)
- `persistence` (lower number = wins ties when two branches claim the same commit)
- `range: (startRow, endRow)`

Default persistence:

| Branch kind | Persistence |
|-------------|-------------|
| Tags | 0 |
| `main`, `master`, `develop` | 1 |
| `release/*`, `hotfix/*` | 2 |
| `feature/*` | 3 |
| Other local branches | 4 |
| Remote branches (`origin/*`) | 5 |
| Merge-summary derived | 6 |

### Phase 3 — Assign branch traces

Sort branches by persistence ascending. For each branch:

1. Start at its tip row.
2. Walk back through the first parent.
3. If a commit has no `branchTrace`, assign this branch and continue.
4. If a commit already has a different trace:
   - If the existing branch has the same name and its range extends past this branch's start, treat it as continuation and update its range.
   - Otherwise stop; this branch's visual range starts just before the collision.

### Phase 4 — Derive source / target branches

- **Target**: if a branch's tip is the second parent of a merge commit, the merge commit's branch becomes this branch's `target_branch`.
- **Source**: if a commit's parent is on a different `branchTrace`, that parent's branch becomes the current branch's `source_branch`.

### Phase 5 — Filter commits

Drop commits whose `branchTrace` is still `nil`. This matches `gleisbau` and keeps the graph tidy. Update row indices and branch ranges to match the filtered list.

### Phase 6 — Assign columns

Default GitFlow order groups (left to right):

| Order group | Patterns |
|-------------|----------|
| 0 | `main`, `master`, `develop` |
| 1 | `release/*`, `hotfix/*` |
| 2 | `feature/*` |
| 3 | other branches, remotes, tags, merge-derived |

Within each group:

1. Sort branches by `(max(sourceOrderGroup, targetOrderGroup), length descending, start ascending)`.
2. Sweep rows. For each branch, find the first column whose occupied ranges do not overlap the branch's `[start, end]`.
3. Prefer right-side placement when the branch's source or target is in a higher-numbered (rightward) group.
4. Avoid placing a branch in the same column as its merge target inside the same group.

After packing each group, convert group-relative columns to absolute columns by adding group offsets.

### Phase 7 — Build paths

Two path types:

1. **Main track**: polyline through all commits of a branch in ascending row order, at the branch's column.
2. **Connector**: for each parent/child relationship across columns, compute `deviateIndex` and build a 4-point SVG-style connector:
   - child at `(row, childColumn)`
   - bend at `(deviateRow, childColumn)`
   - bend at `(deviateRow + 1, parentColumn)`
   - parent at `(parentRow, parentColumn)`

`deviateIndex` rules (from `gleisbau`):

- **Merge commits** (secondary parent): `max(childRow, latestSiblingRowOnParentColumn)`.
- **Normal commits / forks**: `parentRow - 1`.

For same-column parent/child relationships, draw a straight vertical line.

### Phase 8 — Render

`BranchGraphCanvas` receives:

- `nodes`: commit dots positioned at `(row, column)`.
- `paths`: main tracks + connectors.
- `laneCount`: number of absolute columns.

Connectors are drawn as the 4-point polylines described above; `BranchGraphCanvas` already supports multi-segment paths with rounded lane-change corners.

## Data structures

```swift
struct CommitVertex {
    let row: Int
    let commit: Commit
    var parents: [Int]      // row indices
    var children: [Int]     // row indices
    var branchTrace: Int?
    var isMerge: Bool
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
```

## Testing

- Merge-summary parsing: cover Git default, GitHub PR, GitLab MR, Bitbucket PR, and `Merge branch 'x' of ...` forms.
- Branch assignment: overlapping refs, same-name continuation, persistence ordering.
- Column packing: avoid overlaps, respect order groups, handle right-alignment hints.
- Deviate index: merge vs fork cases, sibling collisions.
- Integration tests with temp git repos containing GitFlow-style history.

## Files affected

- `macgit/Views/History/CommitGraphLayoutEngine.swift` — full rewrite.
- `macgit/Views/History/CommitGraphTypes.swift` — update `GraphNode`, `GraphPath`, `CommitGraphLayout` if needed.
- `macgit/Views/History/BranchGraphCanvas.swift` — adjust connector path handling for 4-point connectors.
- `macgitTests/CommitGraphLayoutEngineTests.swift` — expand to cover new algorithm.
- `macgit/Services/GitStatusService+Refs.swift` — new extension to enumerate local branches, remote branches, and tags (if not already available).

## Notes

- macgit paginates history. The layout runs on the currently loaded commit window, so columns may shift slightly when older commits are loaded. This is acceptable and matches the behavior of rendering a windowed subset.
- Remote branch names keep the `origin/` prefix so the default order group regexes still classify them correctly.
