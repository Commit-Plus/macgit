# Change: Add Push Modal Dialog with Branch Selection

## Why
The current Push toolbar button executes `git push` immediately for the current branch only. Users need a modal dialog to choose which local branches to push, verify remote mappings, set upstream tracking, and optionally push all tags—similar to SourceTree's push dialog.

## What Changes
- Replace the one-click Push toolbar action with a modal sheet.
- Create `PushSheetView` with:
  - Remote repository picker (reads `git remote`)
  - Branches to push list with checkboxes, showing local branch name and mapped remote branch
  - "Select All" checkbox
  - "Push all tags" toggle
  - Cancel / OK buttons
- After OK, execute `git push <remote> <local>:<remote>` for each selected branch.
- Show a result popup when Push completes:
  - If nothing to push: "Everything up-to-date."
  - If pushed successfully: "Push completed successfully."
  - On error: existing error alert.

## Impact
- Affected specs: `git-remote-sync`
- Affected code:
  - `macgit/Views/MainWindow/MainWindowView.swift`
  - `macgit/Services/SyncState.swift`
  - `macgit/Services/GitStatusService.swift`
  - New `macgit/Views/Common/PushSheetView.swift`

## Assumptions
- Default remote is `origin`.
- For each selected branch, if it has an upstream, push to that upstream branch name; otherwise push to same-named branch on remote.
- "Track" sets upstream tracking for new branches.
