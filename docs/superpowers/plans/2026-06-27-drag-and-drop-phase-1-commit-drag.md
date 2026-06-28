# Drag and Drop Phase 1 Commit Drag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Select one or more non-merge commits in History, drag them onto any local branch to confirm a batch cherry-pick, or drag one commit onto BRANCHES to create a branch from it.

**Architecture:** Introduce one repository-scoped transferable payload, a pure drop policy, and a testable History selection value. `SidebarView` validates and forwards drops; `MainWindowView` owns confirmation and execution; Git services and the undo executor own batch cherry-pick commands and guarded undo/redo.

**Tech Stack:** Swift, SwiftUI, CoreTransferable, UniformTypeIdentifiers, XCTest, real Git repositories, `xcodebuild`.

**Design spec:** [2026-06-27-drag-and-drop-design.md](../specs/2026-06-27-drag-and-drop-design.md)

---

## Prerequisites

- Branch: `codex/drag-and-drop-phase-1-commit-drag`.
- Worktree: `.worktrees/drag-and-drop-phase-1-commit-drag`.
- Create it from current `main` with `superpowers:using-git-worktrees` when execution begins.
- Mark Phase 1 `[in progress]` with the worktree name before code edits.

## File Structure

- Create `macgit/Models/GitDragDropModels.swift`: payload, target, request, decision, and branch start-point types.
- Create `macgit/Services/GitDragDropPolicy.swift`: pure repository, target, cardinality, and merge-commit validation.
- Create `macgit/Views/History/HistoryCommitSelection.swift`: plain/Command/Shift selection and drag order.
- Modify `macgit/Views/Common/View+ClickInteraction.swift`: expose modifier flags.
- Modify `macgit/Views/History/HistoryView.swift`: selection and commit drag source.
- Modify `macgit/Services/GitStatusService+Diff.swift`: batch cherry-pick API.
- Modify `macgit/Services/GitUndoModels.swift` and `GitUndoExecutor.swift`: batch cherry-pick redo.
- Create `macgit/Views/Common/GitDragActionConfirmationSheet.swift`: commit confirmation.
- Modify `macgit/Views/Common/BranchSheetView.swift`: initial branch start ref.
- Modify `macgit/Views/MainWindow/SidebarView.swift`: local branch and BRANCHES targets.
- Modify `macgit/Views/MainWindow/MainWindowView.swift`: request coordination and execution.
- Create `macgitTests/GitDragDropPolicyTests.swift` and `HistoryCommitSelectionTests.swift`.
- Create `macgitTests/BranchSheetInitialStateTests.swift`: dropped commit preselection.
- Modify `macgitTests/GitUndoExecutorTests.swift` and `GitUndoHistoryIntegrationTests.swift`.
- Modify the drag-and-drop roadmap status.

## Task 1: Add Transferable Payload and Commit Drop Policy

**Files:**
- Create: `macgitTests/GitDragDropPolicyTests.swift`
- Create: `macgit/Models/GitDragDropModels.swift`
- Create: `macgit/Services/GitDragDropPolicy.swift`

- [x] **Step 1: Write failing policy tests**

Cover repository mismatch, commit-to-current acceptance, commit-to-non-current acceptance, merge-commit rejection, one-commit branch creation, and multi-commit branch-creation rejection:

```swift
func testCommitsCanDropOnCurrentBranchInSameRepository() {
    let payload = GitDragPayload.commits(
        [GitDraggedCommit(hash: "c2", message: "second", isMerge: false)],
        repositoryURL: repoURL
    )

    XCTAssertEqual(
        GitDragDropPolicy.decision(
            for: payload,
            target: .localBranch(name: "main", isCurrent: true),
            receivingRepositoryURL: repoURL,
            optionKeyPressed: false
        ),
        .accept(.cherryPick(commits: payload.commits, targetBranch: "main"))
    )
}

func testMergeCommitIsRejectedForCherryPick() {
    XCTAssertEqual(
        decision(commits: [.init(hash: "merge", message: "merge", isMerge: true)]),
        .reject("Merge commits are not supported by drag and drop yet.")
    )
}
```

- [x] **Step 2: Run the test and verify failure**

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitDragDropPolicyTests
```

Expected: compile failure because the payload and policy types do not exist.

- [x] **Step 3: Implement the shared model shapes**

Create the model with this contract:

```swift
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let macgitGitDragPayload = UTType(exportedAs: "com.thanhtran.macgit.git-drag-payload")
}

nonisolated struct GitDraggedCommit: Codable, Hashable, Sendable {
    let hash: String
    let message: String
    let isMerge: Bool
}

nonisolated struct GitDragPayload: Codable, Hashable, Sendable, Transferable {
    enum Content: Codable, Hashable, Sendable {
        case commits([GitDraggedCommit])
        case branch(String)
        case files([String])
        case stash(String)
    }

    let repositoryPath: String
    let content: Content

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .macgitGitDragPayload)
    }

    static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

nonisolated enum GitDragTarget: Equatable, Sendable {
    case localBranch(name: String, isCurrent: Bool)
    case branchesHeader
    case stashesHeader
    case fileStatus
}

nonisolated enum GitBranchStartPoint: Equatable, Sendable {
    case commit(hash: String, message: String)
    case branch(String)
}

nonisolated enum GitDragBranchOperation: Equatable, Sendable {
    case merge
    case rebase
}

nonisolated enum GitDragDropRequest: Equatable, Sendable {
    case cherryPick(commits: [GitDraggedCommit], targetBranch: String)
    case createBranch(startPoint: GitBranchStartPoint)
    case branchOperation(source: String, target: String, operation: GitDragBranchOperation)
    case stashFiles(paths: [String])
    case applyStash(ref: String)
}

nonisolated enum GitDragDropDecision: Equatable, Sendable {
    case accept(GitDragDropRequest)
    case reject(String)
}
```

Add factories and accessors for each payload content without force casts.

- [x] **Step 4: Implement Phase 1 policy cases**

First reject mismatched normalized repository paths. Support `.commits` to any local branch and exactly one commit to `.branchesHeader`. Reject empty batches, merge commits, and unsupported Phase 2/3 combinations with stable tested messages.

- [x] **Step 5: Run policy tests and commit**

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitDragDropPolicyTests
git add macgit/Models/GitDragDropModels.swift macgit/Services/GitDragDropPolicy.swift macgitTests/GitDragDropPolicyTests.swift
git commit -m "feat: add drag payload and drop policy"
```

Expected: tests pass and commit succeeds.

## Task 2: Add Testable History Multi-Selection

**Files:**
- Create: `macgitTests/HistoryCommitSelectionTests.swift`
- Create: `macgit/Views/History/HistoryCommitSelection.swift`
- Modify: `macgit/Views/Common/View+ClickInteraction.swift`
- Modify: `macgit/Views/History/HistoryView.swift`

- [x] **Step 1: Write selection tests**

Cover plain replacement, Command toggle, Shift visible range, primary hash, pruning after reload, selected-row drag, unselected-row fallback, and oldest-first output:

```swift
func testDragSelectionReturnsOldestFirst() {
    var selection = HistoryCommitSelection()
    let visible = ["newest", "middle", "oldest"]
    selection.select("newest", modifiers: [], visibleHashes: visible)
    selection.select("oldest", modifiers: [.command], visibleHashes: visible)

    XCTAssertEqual(
        selection.draggedHashes(startingAt: "newest", visibleHashes: visible),
        ["oldest", "newest"]
    )
}
```

- [x] **Step 2: Run and verify failure**

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/HistoryCommitSelectionTests
```

Expected: compile failure because `HistoryCommitSelection` is missing.

- [x] **Step 3: Implement selection value**

Define an `OptionSet` with `.command` and `.shift`. Store `selectedHashes`, `primaryHash`, and `anchorHash`. Shift selects the inclusive visible range; Command toggles; plain click replaces. `draggedHashes` filters visible hashes and reverses the newest-first display order.

- [x] **Step 4: Pass click modifiers without intercepting native dragging**

Use a native SwiftUI tap gesture and read `NSEvent.modifierFlags` when applying History row selection. Do not place the custom `NSViewRepresentable` click overlay above a draggable row: it becomes the AppKit hit-test target and prevents SwiftUI's drag recognizer from starting the preview session.

- [x] **Step 5: Integrate History selection, payload, and polished preview**

Add `@State private var commitSelection`. Route row clicks through it, update `selectedCommit` from `primaryHash`, prune after history reload, and attach `.draggable` with a commit card preview. The card shows subject, short hash, author, and relative time; multi-selection uses stacked cards with an `N commits` badge. Track the active drag hashes so source rows dim for the duration of the drag. Convert selected hashes to `GitDraggedCommit` in normalized oldest-first order.

Pointer-following preview visibility, source-row dimming through drop/cancel, and appearance in light and dark mode require manual pointer-level QA; unit tests cover the preview presentation data but cannot inspect the native drag image lifecycle.

- [x] **Step 6: Run focused tests and commit**

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/HistoryCommitSelectionTests -only-testing:macgitTests/HistoryViewTests
git add macgit/Views/History/HistoryCommitSelection.swift macgit/Views/Common/View+ClickInteraction.swift macgit/Views/History/HistoryView.swift macgitTests/HistoryCommitSelectionTests.swift
git commit -m "feat: add history commit drag selection"
```

## Task 3: Add Batch Cherry-Pick and Guarded Redo

**Files:**
- Modify: `macgit/Services/GitStatusService+Diff.swift`
- Modify: `macgit/Services/GitUndoModels.swift`
- Modify: `macgit/Services/GitUndoExecutor.swift`
- Modify: `macgitTests/GitUndoExecutorTests.swift`
- Modify: `macgitTests/GitUndoHistoryIntegrationTests.swift`

- [x] **Step 1: Add failing executor and integration tests**

Assert `.cherryPickCommits(commits: ["old", "new"])` records:

```swift
GitCommandCall(arguments: ["cherry-pick", "old", "new"], directory: repoURL)
```

In a real repository, create two feature commits, cherry-pick both, assert both files exist, guarded-reset to old HEAD, redo the batch, and assert both return.

- [x] **Step 2: Verify tests fail**

Run `GitUndoExecutorTests` and `GitUndoHistoryIntegrationTests`. Expected: compile failure because `.cherryPickCommits` is missing.

- [x] **Step 3: Implement service and undo operation**

```swift
func cherryPickCommits(_ commits: [String], in repositoryURL: URL) async throws {
    guard !commits.isEmpty else {
        throw GitError.commandFailed("Select at least one commit to cherry-pick.")
    }
    _ = try await runGit(arguments: ["cherry-pick"] + commits, in: repositoryURL)
}
```

Keep `cherryPickCommit(_:)` as a one-element wrapper. Add `case cherryPickCommits(commits: [String])` and execute one ordered Git command.

- [x] **Step 4: Run tests and commit**

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitUndoExecutorTests -only-testing:macgitTests/GitUndoHistoryIntegrationTests
git add macgit/Services/GitStatusService+Diff.swift macgit/Services/GitUndoModels.swift macgit/Services/GitUndoExecutor.swift macgitTests/GitUndoExecutorTests.swift macgitTests/GitUndoHistoryIntegrationTests.swift
git commit -m "feat: add batch cherry-pick undo support"
```

## Task 4: Wire Commit Drop Targets and Confirmations

**Files:**
- Create: `macgit/Views/Common/GitDragActionConfirmationSheet.swift`
- Modify: `macgit/Views/Common/BranchSheetView.swift`
- Modify: `macgit/Views/MainWindow/SidebarView.swift`
- Modify: `macgit/Views/MainWindow/MainWindowView.swift`
- Modify: `macgitTests/GitDragDropPolicyTests.swift`
- Create: `macgitTests/BranchSheetInitialStateTests.swift`

- [x] **Step 1: Add branch-start resolver tests**

Test `BranchSheetInitialState.resolve(initialStartPoint:recentCommits:)`: a dropped commit sets `useWorkingCopyParent = false`, selects its hash, and inserts it when absent from recent commits.

- [x] **Step 2: Extend BranchSheetView**

Add `initialStartPoint: GitBranchStartPoint? = nil`. Initialize create state from the resolver and ensure `loadCreateData()` preserves the dropped ref rather than replacing it with the newest commit.

- [x] **Step 3: Build commit confirmation UI**

The new sheet receives ordered commits and target branch, lists each short hash and subject, and offers Cancel plus `Cherry-pick N Commits`. It contains no Git calls and disables confirmation while running.

- [x] **Step 4: Add modern sidebar targets**

Add `onRequestGitDrop: (GitDragDropRequest) -> Void`. Attach `dropDestination(for:isEnabled:action:)` to every local branch row and the BRANCHES header. Run policy in the action and forward only `.accept`. Use `onDropSessionUpdated`: `.entering` and `.active` show a strong fill, border, and action label; `.exiting`, `.ended`, and `.dataTransferCompleted` clear it.

- [x] **Step 5: Execute requests in MainWindowView**

Store pending drag request and branch start point. Before cherry-pick, recheck `syncState.isAnySyncing`, `syncState.inProgressOperation`, and conflicts. Capture the target branch HEAD, check out a non-current target after confirmation, call `cherryPickCommits`, and register one reset/redo entry. A create-branch request presents the existing sheet with its initial start point.

- [x] **Step 6: Handle failure state**

On conflict, refresh `SyncState`, select File status, show conflict guidance, and register no undo. If the target branch disappeared or another operation is active, show an error without cherry-picking.

- [x] **Step 7: Run focused tests, build, and commit**

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitDragDropPolicyTests -only-testing:macgitTests/HistoryCommitSelectionTests -only-testing:macgitTests/BranchSheetInitialStateTests -only-testing:macgitTests/GitUndoHistoryIntegrationTests
xcodebuild build -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS'
git add macgit/Views/Common/GitDragActionConfirmationSheet.swift macgit/Views/Common/BranchSheetView.swift macgit/Views/MainWindow/SidebarView.swift macgit/Views/MainWindow/MainWindowView.swift macgitTests/GitDragDropPolicyTests.swift macgitTests/BranchSheetInitialStateTests.swift
git commit -m "feat: confirm commit drag actions"
```

## Task 5: Full Verification and Roadmap Status

**Files:**
- Modify: `docs/superpowers/plans/2026-06-27-drag-and-drop-roadmap.md`

- [x] **Step 1: Run full tests**

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test
```

Expected: `** TEST SUCCEEDED **`.

- [x] **Step 2: Mark Phase 1 completed and commit**

Change the marker to `[completed]` with branch metadata; append the merge commit after landing on `main`.

```bash
git add docs/superpowers/plans/2026-06-27-drag-and-drop-roadmap.md
git commit -m "docs: complete drag and drop phase 1"
```

- [x] **Step 3: Merge and verify main**

Merge the verified branch into `main`, rerun full tests on the root checkout, and do not begin Phase 2 until it passes.
