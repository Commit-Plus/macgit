## 1. Backend Service Extensions
- [ ] 1.1 Add `localBranches(in:)` to `GitStatusService` that returns `[String]` from `git branch`.
- [ ] 1.2 Add `upstreamBranch(for:in:)` to `GitStatusService` that returns the upstream branch name.
- [ ] 1.3 Add `push(remote:branches:pushTags:in:)` to `GitStatusService` that pushes selected branches and optionally tags.

## 2. Push Sheet View
- [ ] 2.1 Create `PushSheetView` with remote picker, branches list with checkboxes, remote branch display, track button, select all, push all tags toggle, Cancel/OK.

## 3. Sync State & MainWindow Updates
- [ ] 3.1 Update `performPush` in `SyncState` to accept remote, branches, pushTags.
- [ ] 3.2 Update Push button in `MainWindowView` to show `PushSheetView`.
- [ ] 3.3 Update `SyncState` to show info popup after push success.

## 4. Validation
- [ ] 4.1 Build with `xcodebuild` and verify no compilation errors.
