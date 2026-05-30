## 1. Backend Service Extensions
- [x] 1.1 Add `remotes(in:)` to `GitStatusService` that returns `[String]` from `git remote`.
- [x] 1.2 Add `remoteBranches(remote:in:)` to `GitStatusService` that returns `[String]` from `git branch -r --list <remote>/*`.
- [x] 1.3 Modify `pull(remote:branch:options:in:)` in `GitStatusService` to accept options and return stdout.

## 2. Pull Sheet View
- [x] 2.1 Create `PullSheetView` with remote picker, branch picker (with refresh), local branch display, options toggles, Cancel/OK.
- [x] 2.2 Options toggles: commitMerged, includeMessages, noFastForward, rebaseInstead.

## 3. Sync State & MainWindow Updates
- [x] 3.1 Add `infoMessage: String?` and `showingInfo: Bool` to `SyncState`.
- [x] 3.2 Update `performPull` in `SyncState` to accept remote, branch, options; show info popup after success.
- [x] 3.3 Update `performFetch` in `SyncState` to show info popup when no new changes.
- [x] 3.4 Replace one-click Pull in `MainWindowView` with sheet presentation of `PullSheetView`.
- [x] 3.5 Bind info alert `.alert("Info", isPresented:)` to `SyncState.showingInfo`.

## 4. Validation
- [x] 4.1 Build with `xcodebuild` and verify no compilation errors.
