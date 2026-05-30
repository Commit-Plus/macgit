# Change: Add Pull Modal Dialog with Options

## Why
The current Pull toolbar button executes `git pull` immediately with no user-configurable options. Users need a modal dialog—similar to SourceTree—that lets them choose the remote repository, select the remote branch, review the local target branch, and configure pull options (e.g. commit merged changes, rebase instead of merge) before executing.

## What Changes
- Replace the one-click Pull toolbar action with a modal sheet.
- Create `PullSheetView` with:
  - Remote repository picker (reads `git remote`)
  - Remote branch picker with Refresh button (reads `git branch -r`)
  - Local branch display (current branch)
  - Options section with toggles:
    - Commit merged changes immediately
    - Include messages from commits being merged in merge commit
    - Create new commit even if fast-forward merge
    - Rebase instead of merge (WARNING)
  - Cancel / OK buttons
- After OK, execute `git pull` with the selected options.
- Show a result popup when Pull completes:
  - If no new changes: "Already up to date."
  - If changes were pulled: "Pull completed successfully."
  - On error/conflict: existing error/conflict alerts.

## Impact
- Affected specs: `git-remote-sync`
- Affected code:
  - `macgit/Views/MainWindow/MainWindowView.swift`
  - `macgit/Services/SyncState.swift`
  - `macgit/Services/GitStatusService.swift`
  - New `macgit/Views/Common/PullSheetView.swift`

## Assumptions
- Default remote is `origin`; if multiple remotes exist, the first is selected by default.
- Default remote branch is the upstream of the current local branch, or the current local branch name.
- The modal uses the existing SwiftUI sheet pattern (`sheet(isPresented:)` or `sheet(item:)`).
