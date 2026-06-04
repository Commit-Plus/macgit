## 1. Data Layer
- [x] 1.1 Add `Commit` model struct (hash, parents, message, author, email, date, refs)
- [x] 1.2 Add `GitStatusService` method: `commitHistory(allBranches: Bool, in: URL) -> [Commit]`
- [x] 1.3 Add `GitStatusService` method: `changedFiles(in commit: String, in: URL) -> [(path: String, status: String)]`
- [x] 1.4 Add `GitStatusService` method: `diff(for file: String, in commit: String, in: URL) -> [DiffHunk]`

## 2. Branch Graph Rendering
- [x] 2.1 Create `CommitGraphLayoutEngine` to assign lane/column positions per commit
- [x] 2.2 Create `BranchGraphCanvas` using `Canvas` to draw smooth bezier branch lines
- [x] 2.3 Assign distinct colors per branch lane with deterministic palette

## 3. History View Components
- [x] 3.1 Create `BranchFilterBar` toggle (All Branches / Current Branch)
- [x] 3.2 Create `CommitGraphListView` combining graph + commit rows in scrollable list
- [x] 3.3 Create `CommitRowView` showing avatar dot, message, author, relative date, hash
- [x] 3.4 Create `CommitDetailPanel` with file changes list and diff viewer
- [x] 3.5 Create `CommitFileListView` showing added/modified/deleted/renamed files
- [x] 3.6 Integrate existing `DiffView` for commit diff display

## 4. History View Integration
- [x] 4.1 Rewrite `HistoryView` as top/bottom `VSplitView` layout
- [x] 4.2 Wire commit selection to update file list and diff viewer
- [x] 4.3 Wire branch filter to reload commit history
- [x] 4.4 Add context menu on commit rows (checkout, cherry-pick, copy hash, copy message)

## 5. Spec & Validation
- [x] 5.1 Update `main-window` spec delta to remove History placeholder
- [x] 5.2 Create `commit-history` spec delta with requirements
- [x] 5.3 Validate with `openspec validate add-history-branch-graph-ui --strict`
- [x] 5.4 Build passes `xcodebuild` without errors
