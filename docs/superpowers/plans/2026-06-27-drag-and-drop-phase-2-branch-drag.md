# Drag and Drop Phase 2 Branch Drag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drag a non-current local branch onto the current branch to confirm Merge or Rebase, or onto BRANCHES to create a new branch from it.

**Architecture:** Extend the Phase 1 payload policy and sidebar targets. `MainWindowView` revalidates source and target, executes existing merge/rebase service calls, and registers expected-HEAD reset entries matching History actions.

**Tech Stack:** Swift, SwiftUI drag/drop, XCTest, real Git repositories, `xcodebuild`.

**Design spec:** [2026-06-27-drag-and-drop-design.md](../specs/2026-06-27-drag-and-drop-design.md)

---

## Prerequisites

- Phase 1 is merged to `main` and full tests pass there.
- Branch: `codex/drag-and-drop-phase-2-branch-drag`.
- Worktree: `.worktrees/drag-and-drop-phase-2-branch-drag`.
- Mark Phase 2 `[in progress]` before implementation.

## File Structure

- Modify `macgit/Services/GitDragDropPolicy.swift`: branch-to-current and branch-to-header decisions.
- Modify `macgit/Views/Common/GitDragActionConfirmationSheet.swift`: Merge/Rebase confirmation.
- Modify `macgit/Views/MainWindow/SidebarView.swift`: branch drag sources and Option-aware drop requests.
- Modify `macgit/Views/MainWindow/MainWindowView.swift`: branch execution, guarded undo, refresh, and conflicts.
- Modify `macgit/Views/Common/BranchSheetView.swift`: display a dropped branch start ref.
- Modify `macgitTests/GitDragDropPolicyTests.swift`.
- Create `macgitTests/GitDragDropBranchIntegrationTests.swift`.
- Modify the drag-and-drop roadmap status.

## Task 1: Extend Policy for Local Branch Payloads

**Files:**
- Modify: `macgitTests/GitDragDropPolicyTests.swift`
- Modify: `macgit/Services/GitDragDropPolicy.swift`

- [ ] **Step 1: Add failing tests**

Assert that a same-repository non-current branch dropped on current accepts Merge, Option accepts Rebase, self-drop rejects, a non-current target rejects, and BRANCHES accepts Create Branch:

```swift
XCTAssertEqual(
    decision(
        branch: "feature",
        target: .localBranch(name: "main", isCurrent: true),
        optionKeyPressed: true
    ),
    .accept(.branchOperation(source: "feature", target: "main", operation: .rebase))
)
```

- [ ] **Step 2: Run and verify failure**

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitDragDropPolicyTests
```

Expected: branch combinations reject as unsupported.

- [ ] **Step 3: Implement branch decisions**

For `.branch(source)`, accept only a current `.localBranch` where `source != target`. Select `.rebase` when `optionKeyPressed`, otherwise `.merge`. Accept `.branchesHeader` as `.createBranch(.branch(source))`. Remote rows never create a local-branch payload.

- [ ] **Step 4: Run tests and commit**

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitDragDropPolicyTests
git add macgit/Services/GitDragDropPolicy.swift macgitTests/GitDragDropPolicyTests.swift
git commit -m "feat: validate branch drag actions"
```

## Task 2: Add Branch Sources and Confirmation UI

**Files:**
- Modify: `macgit/Views/MainWindow/SidebarView.swift`
- Modify: `macgit/Views/Common/GitDragActionConfirmationSheet.swift`
- Modify: `macgit/Views/Common/BranchSheetView.swift`

- [ ] **Step 1: Make local branch rows draggable**

Attach a branch payload to each non-folder local row. The current branch remains draggable for Create Branch, while policy rejects self merge/rebase.

- [ ] **Step 2: Capture Option at drop**

Pass `NSEvent.modifierFlags.contains(.option)` into policy from the current-branch destination. The resulting request stores the operation so releasing Option after the drop cannot change confirmation semantics.

- [ ] **Step 3: Extend confirmation UI**

Render source and target plus a Merge/Rebase picker initialized from the request. The explanatory line must be exact:

```swift
operation == .merge
    ? "Merge \(source) into \(target)"
    : "Rebase \(target) onto \(source)"
```

Allow changing the operation before confirmation.

- [ ] **Step 4: Preserve branch start point in Create Branch**

When `.branch("feature")` is supplied, insert `BranchCommitInfo(hash: "feature", message: "Branch")` if absent and select it without changing the existing create call.

- [ ] **Step 5: Build and commit**

```bash
xcodebuild build -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS'
git add macgit/Views/MainWindow/SidebarView.swift macgit/Views/Common/GitDragActionConfirmationSheet.swift macgit/Views/Common/BranchSheetView.swift
git commit -m "feat: add branch drag confirmations"
```

## Task 3: Execute Merge/Rebase with Guarded Undo

**Files:**
- Create: `macgitTests/GitDragDropBranchIntegrationTests.swift`
- Modify: `macgit/Views/MainWindow/MainWindowView.swift`

- [ ] **Step 1: Write real-repository tests**

Create divergent `main` and `feature` branches. For Merge, assert `main` moves, `feature` does not, and expected-HEAD reset restores main. For Rebase, check out main, rebase onto feature, assert main is a descendant of feature, and guarded-reset to old main.

```swift
XCTAssertEqual(try git(["rev-parse", "feature"], in: repoURL), featureTip)
XCTAssertEqual(try git(["merge-base", "--is-ancestor", "feature", "main"], in: repoURL), "")
```

Use termination status rather than stdout for the `merge-base --is-ancestor` assertion if the shared helper cannot expose both.

- [ ] **Step 2: Run service-level baseline**

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitDragDropBranchIntegrationTests
```

Expected: tests pass using existing merge/rebase/reset executor operations before UI wiring.

- [ ] **Step 3: Add MainWindow execution**

Before Git, require source and target to remain local, target to equal current branch, no sync/in-progress operation, and no unresolved conflicts. Capture old HEAD. Merge calls `mergeCommit(source, noCommit: false, log: false)`; Rebase calls `rebaseCommit(source)`.

After success, capture new HEAD and register:

```swift
GitUndoEntry(
    repositoryURL: repositoryURL,
    label: operation == .merge ? "Merge \(source)" : "Rebase onto \(source)",
    undoOperation: .resetHead(target: oldHead, mode: .hard, expectedHead: newHead),
    redoOperation: operation == .merge
        ? .mergeCommit(commit: source, noCommit: false, log: false)
        : .rebaseOnto(commit: source)
)
```

- [ ] **Step 4: Handle conflicts**

Refresh `SyncState`, select File status, call `showConflict`, register no undo entry, and always clear the pending request/running flag.

- [ ] **Step 5: Run focused tests and commit**

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitDragDropPolicyTests -only-testing:macgitTests/GitDragDropBranchIntegrationTests -only-testing:macgitTests/GitUndoHistoryIntegrationTests
git add macgit/Views/MainWindow/MainWindowView.swift macgitTests/GitDragDropBranchIntegrationTests.swift
git commit -m "feat: execute branch drag actions"
```

## Task 4: Full Verification and Roadmap Status

**Files:**
- Modify: `docs/superpowers/plans/2026-06-27-drag-and-drop-roadmap.md`

- [ ] **Step 1: Run full tests**

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 2: Mark Phase 2 completed and commit**

Add branch metadata, then append the merge commit after landing on `main`.

```bash
git add docs/superpowers/plans/2026-06-27-drag-and-drop-roadmap.md
git commit -m "docs: complete drag and drop phase 2"
```

- [ ] **Step 3: Merge and verify main**

Merge to `main`, rerun full tests on the root checkout, and start Phase 3 only after success.
