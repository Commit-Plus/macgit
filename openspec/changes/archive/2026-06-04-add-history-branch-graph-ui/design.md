## Context
macgit is a SwiftUI macOS app. The History view is currently a placeholder. We need to implement a SourceTree-like commit history with branch graph visualization.

## Goals / Non-Goals
- Goals:
  - Display commit history with visual branch graph using smooth curves
  - Show commit details and file-level diffs in a bottom panel
  - Provide branch filter (All / Current)
  - Provide commit context menu actions
- Non-Goals:
  - Interactive rebase via graph
  - Drag-and-drop branch manipulation
  - Subgraph filtering by author or date range

## Decisions
- **Graph Rendering: Canvas + Lane Layout**
  - Use SwiftUI `Canvas` for drawing smooth bezier branch lines between commits
  - Build a lane-based layout engine from commit parent relationships
  - Rationale: `Canvas` gives precise control over curves and anti-aliasing; lane layout is deterministic and easier to implement than force-directed graphs
  - Alternative considered: ASCII art parsing from `git log --graph` — rejected because it produces jagged lines and is hard to style
- **Data Source: Custom Git Log Parsing**
  - Use `git log --all --format="%H|%P|%s|%an|%ae|%ad|%D"` to get structured commit data
  - Rationale: gives us full control over graph topology
- **Diff Reuse: Existing `DiffView`**
  - Use the existing `DiffView` component for commit diffs
  - Only add a thin wrapper `CommitDiffView` to call the right Git service method
- **Layout: VSplitView + HSplitView**
  - Top 60-70%: `CommitGraphListView` inside scrollable area
  - Bottom 30-40%: `HSplitView` with file list (left) and diff viewer (right)
  - Rationale: matches SourceTree layout exactly and reuses native macOS split view behaviors

## Risks / Trade-offs
- **Complexity of graph layout engine** → Mitigation: start with a simple greedy lane assignment; document that complex cross-merges may have suboptimal crossing
- **Performance with large repositories** → Mitigation: virtualized scrolling with `LazyVStack`; lazy load diff content

## Open Questions
- None (clarified with user)
