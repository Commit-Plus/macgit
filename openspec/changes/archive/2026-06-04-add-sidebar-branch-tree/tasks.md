## 1. Data Model & Selection State
- [x] 1.1 Introduce `SidebarSelection` enum wrapping `SidebarItem` and `String` branch names
- [x] 1.2 Introduce `BranchNode` struct for tree representation (folder vs leaf)
- [x] 1.3 Add `branchFilter: String?` parameter to `HistoryView` init

## 2. Git Service Updates
- [x] 2.1 Add `commitHistory(branch: String, in:)` overload to `GitStatusService` that runs `git log <branch> …`
- [x] 2.2 Verify existing `checkoutCommit` works for branch checkout (or add `checkoutBranch` if needed)

## 3. Sidebar View (`SidebarView.swift`)
- [x] 3.1 Replace `SidebarItem?` binding with `SidebarSelection?` binding
- [x] 3.2 Add `@State` for local branches, current branch, and expanded folder set
- [x] 3.3 Build `BranchNode` tree from flat branch list on load / refresh
- [x] 3.4 Render BRANCHES section with recursive folder/leaf rows using `DisclosureGroup` or custom expand/collapse
- [x] 3.5 Handle single-click selection (tag as `.branch(name)`)
- [x] 3.6 Handle double-click for checkout (skip if already current)
- [x] 3.7 Add context menu to branch leaf rows with listed actions
- [x] 3.8 Show circle icon + bold text for current branch
- [x] 3.9 Keep other sections as disabled placeholders
- [x] 3.10 Add checkout confirmation dialog with "Stash local changes" option

## 4. Main Window Routing (`MainWindowView.swift`)
- [x] 4.1 Update `selectedItem` state to `SidebarSelection?`
- [x] 4.2 Route `.branch(name)` selection to `HistoryView(repositoryURL: branchFilter: name)`
- [x] 4.3 Keep existing `.item(.fileStatus)`, `.item(.history)`, `.item(.search)` routing unchanged
- [x] 4.4 Wire branch selection to trigger `SyncState.refresh` after checkout

## 5. History View Filter (`HistoryView.swift`)
- [x] 5.1 Accept optional `branchFilter: String?` init parameter
- [x] 5.2 When `branchFilter` is set, call `commitHistory(branch:)` and hide the "All Branches / Current Branch" picker
- [x] 5.3 When `branchFilter` is nil, preserve existing behavior

## 6. Validation
- [x] 6.1 Build project with `xcodebuild` (or Xcode) and confirm no compile errors
- [ ] 6.2 Manual test: open a repo with slash-named branches, verify tree rendering
- [ ] 6.3 Manual test: single-click branch → History filtered correctly
- [ ] 6.4 Manual test: double-click branch → checkout succeeds, UI refreshes
- [ ] 6.5 Manual test: right-click → context menu appears with expected items
- [ ] 6.6 Manual test: current branch shows circle icon and bold text
