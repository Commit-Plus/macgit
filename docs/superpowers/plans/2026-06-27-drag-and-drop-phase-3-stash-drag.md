# Drag and Drop Phase 3 Stash Drag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drag selected File status paths onto STASHES to create a path-scoped stash, and drag a stash onto File status to apply it without deleting it.

**Architecture:** Reuse the Phase 1 payload and policy. File drag selection comes from `FileStatusActionSelection`; path-scoped options flow through `StashSheetView`, `SyncState`, `GitStatusService`, and `GitUndoOperation`; stash apply forwards to existing confirmation and safety logic.

**Tech Stack:** Swift, SwiftUI drag/drop, XCTest, `git stash push -- <paths>`, real Git repositories, `xcodebuild`.

**Design spec:** [2026-06-27-drag-and-drop-design.md](../specs/2026-06-27-drag-and-drop-design.md)

---

## Prerequisites

- Phases 1 and 2 are merged to `main` and full tests pass.
- Branch: `codex/drag-and-drop-phase-3-stash-drag`.
- Worktree: `.worktrees/drag-and-drop-phase-3-stash-drag`.
- Mark Phase 3 `[in progress]` before implementation.

## File Structure

- Modify `macgit/Services/GitDragDropPolicy.swift`: files-to-STASHES and stash-to-File-status decisions.
- Modify `macgit/Views/FileStatus/FileStatusActionSelection.swift`: deterministic drag path resolution.
- Modify `macgit/Views/FileStatus/FileStatusView.swift`: file drag sources.
- Modify `macgit/Views/MainWindow/SidebarView.swift`: STASHES/File status targets and stash source.
- Modify `macgit/Views/Common/StashSheetView.swift`: selected-path context and options.
- Modify `macgit/Services/GitStatusService.swift`: path and include-untracked stash options.
- Modify `macgit/Services/GitStatusService+MergeStash.swift`: path-scoped command.
- Modify `macgit/Services/SyncState.swift`: path-preserving redo metadata.
- Modify `macgit/Services/GitUndoModels.swift` and `GitUndoExecutor.swift`: path-scoped stash redo.
- Modify `macgit/Views/MainWindow/MainWindowView.swift`: route stash-file and apply requests.
- Modify `macgitTests/GitDragDropPolicyTests.swift`, `FileStatusActionSelectionTests.swift`, `GitUndoExecutorTests.swift`, `StashServiceTests.swift`, and `GitUndoStashSaveDropTests.swift`.
- Modify the drag-and-drop roadmap status.

## Task 1: Add Stash Drop Policy Cases

**Files:**
- Modify: `macgitTests/GitDragDropPolicyTests.swift`
- Modify: `macgit/Services/GitDragDropPolicy.swift`

- [ ] **Step 1: Add failing policy tests**

Assert same-repository files to STASHES accepts `stashFiles`, empty paths reject, stash to File status accepts `applyStash`, and inverse/other targets reject:

```swift
XCTAssertEqual(
    decision(payload: .files(["a.txt", "b.txt"], repositoryURL: repoURL), target: .stashesHeader),
    .accept(.stashFiles(paths: ["a.txt", "b.txt"]))
)

XCTAssertEqual(
    decision(payload: .stash("stash@{0}", repositoryURL: repoURL), target: .fileStatus),
    .accept(.applyStash(ref: "stash@{0}"))
)
```

- [ ] **Step 2: Run and verify failure**

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitDragDropPolicyTests
```

Expected: Phase 3 combinations reject as unsupported.

- [ ] **Step 3: Implement and commit**

Normalize file paths by removing empty values while preserving first-seen order. Keep repository validation first.

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitDragDropPolicyTests
git add macgit/Services/GitDragDropPolicy.swift macgitTests/GitDragDropPolicyTests.swift
git commit -m "feat: validate stash drag actions"
```

## Task 2: Resolve and Drag Selected File Paths

**Files:**
- Modify: `macgitTests/FileStatusActionSelectionTests.swift`
- Modify: `macgit/Views/FileStatus/FileStatusActionSelection.swift`
- Modify: `macgit/Views/FileStatus/FileStatusView.swift`

- [ ] **Step 1: Add failing drag-path tests**

Cover selected-row carrying all selected files, unselected-row carrying only fallback, staged/changed duplicate removal, and rename inclusion of old and new paths:

```swift
XCTAssertEqual(
    selection.dragPaths(startingAt: renamed, isStaged: true),
    ["old-name.txt", "new-name.txt"]
)
```

- [ ] **Step 2: Implement `dragPaths`**

Resolve the same fallback rule used by context actions, combine each file's `originalPath` then `path`, remove empty values, and preserve first-seen order.

- [ ] **Step 3: Add file row payload**

Attach `.draggable` to row content after checkbox/button interactions. Build `.files(paths)` from `actionSelection.dragPaths(startingAt:isStaged:)` and show one filename or `N files` in the preview.

- [ ] **Step 4: Run tests and commit**

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/FileStatusActionSelectionTests
git add macgit/Views/FileStatus/FileStatusActionSelection.swift macgit/Views/FileStatus/FileStatusView.swift macgitTests/FileStatusActionSelectionTests.swift
git commit -m "feat: add working copy file drag payloads"
```

## Task 3: Add Path-Scoped Stash Service and Redo

**Files:**
- Modify: `macgit/Services/GitStatusService.swift`
- Modify: `macgit/Services/GitStatusService+MergeStash.swift`
- Modify: `macgit/Services/GitUndoModels.swift`
- Modify: `macgit/Services/GitUndoExecutor.swift`
- Modify: `macgit/Services/SyncState.swift`
- Modify: `macgitTests/GitUndoExecutorTests.swift`
- Modify: `macgitTests/StashServiceTests.swift`
- Modify: `macgitTests/GitUndoStashSaveDropTests.swift`

- [ ] **Step 1: Add failing command and integration tests**

Assert redo records exactly:

```swift
["stash", "push", "--include-untracked", "-m", "Selected files", "--", "tracked.txt", "new.txt"]
```

In `StashServiceTests`, modify two tracked files and create two untracked files. Stash one tracked and one untracked path. Assert selected paths become clean/missing, unrelated changes remain, and applying the stash restores selected content.

- [ ] **Step 2: Extend stash options**

Use defaulted fields so existing callers retain behavior:

```swift
struct StashOptions {
    var message: String = ""
    var keepIndex: Bool = false
    var paths: [String] = []
    var includeUntracked: Bool = false
}
```

- [ ] **Step 3: Build command arguments**

Append `--include-untracked` when requested, then message, then `--` and normalized paths when non-empty. Continue using `Process.arguments`; never quote or join paths into a shell string.

- [ ] **Step 4: Preserve redo metadata**

Change `.stashPush` to carry `message`, `keepIndex`, `paths`, and `includeUntracked`. Update all pattern matches and callers. `SyncState.performStash` registers exactly the options used by the original action.

- [ ] **Step 5: Run tests and commit**

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitUndoExecutorTests -only-testing:macgitTests/StashServiceTests -only-testing:macgitTests/GitUndoStashSaveDropTests
git add macgit/Services/GitStatusService.swift macgit/Services/GitStatusService+MergeStash.swift macgit/Services/GitUndoModels.swift macgit/Services/GitUndoExecutor.swift macgit/Services/SyncState.swift macgitTests/GitUndoExecutorTests.swift macgitTests/StashServiceTests.swift macgitTests/GitUndoStashSaveDropTests.swift
git commit -m "feat: stash selected working copy paths"
```

## Task 4: Wire STASHES and File Status Drop Targets

**Files:**
- Modify: `macgit/Views/Common/StashSheetView.swift`
- Modify: `macgit/Views/MainWindow/SidebarView.swift`
- Modify: `macgit/Views/MainWindow/MainWindowView.swift`

- [ ] **Step 1: Adapt StashSheetView**

Add `paths: [String] = []`. When non-empty, show `Stash N selected files`, include paths in `StashOptions`, and set `includeUntracked = true`. Toolbar stash passes an empty path list and retains current behavior.

- [ ] **Step 2: Add STASHES target**

Attach an enabled drop destination to the STASHES header. Forward accepted `.stashFiles` to MainWindow and show `Stash N files` during `.entering`/`.active` drop phases.

- [ ] **Step 3: Add stash source and File status target**

Make `stashRowView` draggable with `.stash(stash.ref)`. Attach a drop destination to the File status workspace label. Forward `.applyStash` to existing `requestStashAction(ref:action:.apply)` so existing confirmation and safe undo checks remain authoritative.

- [ ] **Step 4: Present path-scoped stash from MainWindow**

Store `pendingStashPaths`. A `.stashFiles` request sets paths and presents `StashSheetView(paths:)`; clear paths on cancel or completion. Reject while `syncState.isAnySyncing` or an in-progress operation exists.

- [ ] **Step 5: Run focused tests, build, and commit**

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitDragDropPolicyTests -only-testing:macgitTests/FileStatusActionSelectionTests -only-testing:macgitTests/StashServiceTests -only-testing:macgitTests/GitUndoStashSaveDropTests
xcodebuild build -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS'
git add macgit/Views/Common/StashSheetView.swift macgit/Views/MainWindow/SidebarView.swift macgit/Views/MainWindow/MainWindowView.swift
git commit -m "feat: wire stash drag and drop"
```

## Task 5: Full Verification and Roadmap Completion

**Files:**
- Modify: `docs/superpowers/plans/2026-06-27-drag-and-drop-roadmap.md`

- [ ] **Step 1: Run full tests**

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 2: Mark Phase 3 completed and commit**

Update Phase 3 with branch metadata and append the merge commit after landing on `main`.

```bash
git add docs/superpowers/plans/2026-06-27-drag-and-drop-roadmap.md
git commit -m "docs: complete drag and drop phase 3"
```

- [ ] **Step 3: Merge and verify main**

Merge the branch into `main` and rerun the full test suite on the root checkout.

- [ ] **Step 4: Manual QA handoff**

Ask the user to verify previews, current-branch-only highlighting, path counts, Option-preselected Rebase, Apply-only stash behavior, and VoiceOver labels. Do not launch the app from the agent workflow.
