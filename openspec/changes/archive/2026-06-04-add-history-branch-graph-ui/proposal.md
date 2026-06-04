# Change: Add History Branch Graph UI

## Why
The History view in macgit is currently an empty placeholder. Users need a visual commit history with branch graph visualization, commit details, and diff viewing — similar to SourceTree — to understand repository evolution and review past changes.

## What Changes
- Replace `HistoryView` placeholder with a full commit history screen featuring:
  - A branch graph visualization with smooth curved branch lines (Canvas-based)
  - A commit list integrated with the graph showing message, author, date, hash
  - A branch filter toggle above the graph (All Branches / Current Branch)
  - A bottom panel split into file changes list (left) and diff viewer (right)
  - Context menu actions on commits (checkout, cherry-pick, copy hash, etc.)
- Add `GitStatusService` methods for commit log retrieval, changed files per commit, and commit diffs
- Follow existing SwiftUI style patterns (glass buttons, thin materials, monospaced fonts, high corner radius)

## Impact
- Affected specs: `main-window`, new `commit-history` capability
- Affected code: `macgit/Views/History/HistoryView.swift`, new components under `macgit/Views/History/`, `macgit/Services/GitStatusService.swift`
