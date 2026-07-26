# SidebarView Refactor Phase 4 Orchestration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move remaining loading, drag/drop, branch, worktree, submodule, and subtree behavior into focused cross-file `SidebarView` extensions, then verify the complete behavior-preserving refactor.

**Architecture:** Stored state, initializer, root composition, lifecycle modifiers, and presentation attachment remain in `SidebarView.swift`. Methods move by behavior into `SidebarView+*.swift`; members shared across those files use module-internal access. No new state owner or Git execution layer is introduced.

**Tech Stack:** SwiftUI, Swift concurrency, AppKit drag/drop and folder panels, existing `GitStatusService`, XCTest, `xcodebuild`.

## Global Constraints

- Start from clean Phase-3-updated `main` on branch `codex/sidebar-refactor-phase-4-orchestration`.
- This phase is a method move and root cleanup, not an architecture or behavior rewrite.
- Cross-file shared seams are internal, never `fileprivate` and never `public`.
- Preserve all `MainActor` hops, task-group concurrency, stale-load IDs, cache calls, notification posts, state-reset order, and error copy.
- Every new Swift file includes the AGPL v3 header.
- Do not launch the app.

---

### Task 1: Audit and expose only required cross-file seams

**Files:**
- Modify: `macgit/Views/MainWindow/SidebarView.swift`

**Interfaces:**
- Stored properties and callbacks used by a `SidebarView+*.swift` extension become internal by removing `private`.
- Properties used only by root composition remain `private`.
- The external initializer and `SidebarView` type visibility do not change.

- [ ] **Step 1: Inventory remaining methods and shared members.**

  Run:

  ```bash
  rg -n '^    (private )?(var|func) ' macgit/Views/MainWindow/SidebarView.swift
  rg -n '^    @State private var|^    let |^    @Binding' macgit/Views/MainWindow/SidebarView.swift
  ```

  Classify every remaining method under Loading, DragDrop, BranchActions, WorktreeActions, SubmoduleActions, SubtreeActions, or root composition.

- [ ] **Step 2: Change access only for members used across files.**

  Use:

  ```swift
  @State var branchNodes: [BranchNode] = []
  let repositoryURL: URL
  let onRequestDragDrop: (GitDragDropRequest) -> Void
  ```

  Do not use `fileprivate`; it cannot be accessed from another Swift file. Do not expose any member as `public`.

- [ ] **Step 3: Build before moving methods.**

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  ```

- [ ] **Step 4: Commit the access-control seam.**

  ```bash
  git add macgit/Views/MainWindow/SidebarView.swift
  git commit -m "refactor: prepare SidebarView extension seams"
  ```

### Task 2: Move loading orchestration

**Files:**
- Create: `macgit/Views/MainWindow/SidebarView+Loading.swift`
- Modify: `macgit/Views/MainWindow/SidebarView.swift:1389-1488,2868-3159`
- Test: `macgitTests/SidebarTreeBuilderTests.swift`
- Test: `macgitTests/SidebarBranchSyncBadgeResolverTests.swift`

**Interfaces:**
- Move unchanged:
  - `resetLazySectionData()`
  - `loadVisibleSections(force:)`
  - `loadAllSections(force:)`
  - `loadSectionIfNeeded(_:)`
  - visible branch/tag/remote row derivation
  - `branchesUnderPrefix(_:)`
  - `loadBranches(force:)`
  - branch-sync startup/loading
  - `loadTags()`
  - `loadRemotes()`
  - `loadStashes()`
  - `collectFolderPaths(from:)`
- Worktree, submodule, and subtree loaders move with their feature actions in later tasks.

- [ ] **Step 1: Move loading methods without rewriting bodies.**

  Start the file with the AGPL header and required imports:

  ```swift
  import Foundation
  import SwiftUI

  extension SidebarView {
      // Existing methods moved unchanged.
  }
  ```

  Preserve `withTaskGroup` fan-out, cached branch APIs, active branch-sync load ID, expansion initialization, and all `MainActor.run` blocks.

- [ ] **Step 2: Keep lifecycle call sites in the root.**

  `.task(id:)`, `.onReceive(.repositoryDidChange)`, and `.onChange(of: appState.showSubtrees)` remain in `SidebarView.swift` and call the moved methods.

- [ ] **Step 3: Run tree/sync tests and build.**

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/SidebarTreeBuilderTests -only-testing:macgitTests/SidebarBranchSyncBadgeResolverTests test
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  ```

- [ ] **Step 4: Commit loading extraction.**

  ```bash
  git add macgit/Views/MainWindow/SidebarView.swift macgit/Views/MainWindow/SidebarView+Loading.swift
  git commit -m "refactor: move SidebarView loading orchestration"
  ```

### Task 3: Move drag/drop orchestration

**Files:**
- Create: `macgit/Views/MainWindow/SidebarView+DragDrop.swift`
- Modify: `macgit/Views/MainWindow/SidebarView.swift:1206-1387,1972-1988`
- Test: `macgitTests/GitDragDropPolicyTests.swift`
- Test: `macgitTests/GitDragDropBranchIntegrationTests.swift`

**Interfaces:**
- Move payload/provider construction, hover updates, `canAcceptDrop`, both `handleDrop` overloads, payload cleanup, and stash provider creation unchanged.
- Components continue consuming the Phase-2 `SidebarDropActions` adapter.

- [ ] **Step 1: Move drag/drop methods as one coherent unit.**

  Preserve:

  ```swift
  switch GitDragDropPolicy.decision(
      for: payload,
      target: target,
      receivingRepositoryURL: repositoryURL,
      optionKeyPressed: optionKeyPressed
  ) {
  case .accept(let request):
      if case .checkoutRemoteBranch = request {
          expandBranchesSection()
      }
      onRequestDragDrop(request)
  case .reject(let reason):
      guard payload.remoteBranch == nil else { return }
      errorMessage = reason
      showingError = true
  }
  ```

  Do not reorder payload-store clearing relative to request handling.

- [ ] **Step 2: Run drag/drop tests and build.**

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitDragDropPolicyTests -only-testing:macgitTests/GitDragDropBranchIntegrationTests test
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  ```

- [ ] **Step 3: Commit drag/drop extraction.**

  ```bash
  git add macgit/Views/MainWindow/SidebarView.swift macgit/Views/MainWindow/SidebarView+DragDrop.swift
  git commit -m "refactor: move SidebarView drag drop orchestration"
  ```

### Task 4: Move branch and remote actions

**Files:**
- Create: `macgit/Views/MainWindow/SidebarView+BranchActions.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarDeleteBranchSheet.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarDeletePrefixSheet.swift`
- Modify: `macgit/Views/MainWindow/SidebarView.swift:1990-2287,2510-2600,2784-2882`
- Test: `macgitTests/SidebarTreeBuilderTests.swift`

**Interfaces:**
- Move folder toggles, remote path parsing, remote checkout/deletion, branch-section expansion, branch/prefix confirmation helpers, branch/prefix deletion, and prefix collection.
- `SidebarDeleteBranchSheet` receives branch name, force binding, Cancel, and Delete callbacks.
- `SidebarDeletePrefixSheet` receives prefix, all/deletable/skipped branch lists, force binding, Cancel, and Delete callbacks.
- Preserve `BranchListCache` invalidation through existing service methods; no view-level cache invalidation is added.

- [ ] **Step 1: Extract the two deletion sheets.**

  Preserve title, confirmation copy, current-branch skipped list, force toggle copy, dimensions, keyboard shortcuts, and destructive button labels. Both views stay rendering-only:

  ```swift
  struct SidebarDeleteBranchSheet: View {
      let branch: String
      @Binding var forceDelete: Bool
      let onCancel: () -> Void
      let onDelete: (Bool) -> Void
  }
  ```

  `SidebarDeletePrefixSheet` follows the same callback shape and receives the three precomputed branch arrays.

- [ ] **Step 2: Move branch and remote methods unchanged.**

  Keep remote checkout order:

  ```text
  checkout remote branch
  expand local branches section
  force-load local branches
  reload remotes
  select the new local branch
  post repositoryDidChange
  ```

  Keep local delete undo registration, error handling, selection fallback, and force toggle reset timing unchanged.

- [ ] **Step 3: Keep extracted menu and sheet views closure-driven.**

  Verify the new extension contains no SwiftUI menu layout:

  ```bash
  rg -n 'Button\\(|Menu\\(|Divider\\(' macgit/Views/MainWindow/SidebarView+BranchActions.swift
  ```

  Expected: no matches. Menus and confirmation sheets live in their dedicated component files.

- [ ] **Step 4: Run tests/build and commit.**

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/SidebarTreeBuilderTests test
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  git add macgit/Views/MainWindow
  git commit -m "refactor: move SidebarView branch actions"
  ```

### Task 5: Move submodule and subtree actions

**Files:**
- Create: `macgit/Views/MainWindow/SidebarView+SubmoduleActions.swift`
- Create: `macgit/Views/MainWindow/SidebarView+SubtreeActions.swift`
- Modify: `macgit/Views/MainWindow/SidebarView.swift:1023-1072,2993-3073`
- Test: `macgitTests/SubmoduleLifecyclePolicyTests.swift`
- Test: `macgitTests/SubtreeSidebarPolicyTests.swift`

**Interfaces:**
- Submodule extension owns `loadSubmodules(force:)`, confirmation decisions, and deinitialize/remove forwarding.
- Subtree extension owns `loadSubtrees(force:)` and unlink execution.

- [ ] **Step 1: Move submodule behavior.**

  Preserve active-load UUID checks, cancellation cleanup, force decision handling, error presentation, and selection fallback after removal.

- [ ] **Step 2: Move subtree behavior.**

  Preserve lazy-load guard, service discovery, unlink callback, root selection update, and error message sanitation.

- [ ] **Step 3: Run focused tests/build and commit.**

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/SubmoduleLifecyclePolicyTests -only-testing:macgitTests/SubtreeSidebarPolicyTests test
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  git add macgit/Views/MainWindow
  git commit -m "refactor: move SidebarView module actions"
  ```

### Task 6: Move worktree behavior

**Files:**
- Create: `macgit/Views/MainWindow/SidebarView+WorktreeActions.swift`
- Modify: `macgit/Views/MainWindow/SidebarView.swift:1490-1538,2993-3008,3161-3576`
- Test: `macgitTests/WorktreeServiceTests.swift`
- Test: `macgitTests/WorktreeLabelStoreTests.swift`

**Interfaces:**
- Move worktree validation, loading, missing-path checks, presentation preparation, label/lock/prune/create/move/repair/checkout/removal methods unchanged.
- Root retains only worktree state declarations and modifier/sheet composition.

- [ ] **Step 1: Move pure worktree calculations first.**

  Move `canCreateWorktree`, `canMoveWorktree`, `canCheckoutWorktreeBranch`, force-removal message, default path/name sanitization, and preferred branch helpers. Build before moving async methods.

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  ```

- [ ] **Step 2: Move interaction and async methods.**

  Preserve `NSOpenPanel` configuration, missing-path revalidation at click time, operation loading flags, `defer` cleanup, service calls, refresh calls, and error destinations.

- [ ] **Step 3: Run worktree tests/build and commit.**

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/WorktreeServiceTests -only-testing:macgitTests/WorktreeLabelStoreTests test
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  git add macgit/Views/MainWindow
  git commit -m "refactor: move SidebarView worktree actions"
  ```

### Task 7: Clean the root and perform final verification

**Files:**
- Modify: `macgit/Views/MainWindow/SidebarView.swift`
- Modify: `docs/superpowers/plans/2026-07-26-sidebar-view-refactor-roadmap.md`
- Inspect: all files under `macgit/Views/MainWindow/Sidebar/`

**Interfaces:**
- `SidebarView.swift` contains stored dependencies/state, initializer, root body/list composition, lifecycle modifiers, presentation attachment, and action-bundle adapters.
- No feature row, menu, sheet, Git operation, or loading implementation remains inline.

- [ ] **Step 1: Remove obsolete helpers/imports and inspect root scope.**

  ```bash
  wc -l macgit/Views/MainWindow/SidebarView.swift
  rg -n '^    (private )?func |@ViewBuilder|AnyView|runGit|GitStatusService\\.shared' macgit/Views/MainWindow/SidebarView.swift
  ```

  Expected: only composition helpers and action-bundle adapters remain; no `AnyView`, direct Git service call, row builder, menu builder, or async feature implementation remains.

- [ ] **Step 2: Run the complete focused sidebar suite.**

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' \
    -only-testing:macgitTests/SidebarTreeBuilderTests \
    -only-testing:macgitTests/SidebarBranchSyncBadgeResolverTests \
    -only-testing:macgitTests/SidebarViewStashTests \
    -only-testing:macgitTests/GitDragDropPolicyTests \
    -only-testing:macgitTests/GitDragDropBranchIntegrationTests \
    -only-testing:macgitTests/WorktreeServiceTests \
    -only-testing:macgitTests/WorktreeLabelStoreTests \
    -only-testing:macgitTests/SubmoduleSidebarPolicyTests \
    -only-testing:macgitTests/SubmoduleLifecyclePolicyTests \
    -only-testing:macgitTests/SubtreeSidebarPolicyTests test
  ```

  Expected: PASS. If the documented test-host `Early unexpected exit` / `abort() called` occurs, record it once and do not rerun the identical suite.

- [ ] **Step 3: Run the required final build.**

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  ```

  Expected: `BUILD SUCCEEDED`. Do not launch `Commit+.app`.

- [ ] **Step 4: Audit invariants and file hygiene.**

  ```bash
  rg -L 'GNU Affero General Public License' macgit/Views/MainWindow/Sidebar --glob '*.swift'
  rg -n 'onTapGesture|simultaneousGesture|onDrop|SidebarBranchDropTarget' macgit/Views/MainWindow/Sidebar
  rg -n 'cachedLocalBranches|cachedRemoteBranches|fetch\\(' macgit/Views/MainWindow/SidebarView+Loading.swift
  git diff main...HEAD --stat
  git diff --check
  git status --short
  ```

  Confirm no implicit fetch was added, every new Swift file has the license header, gesture/drop ownership is present in extracted rows/sections, and no unrelated files changed.

- [ ] **Step 5: Commit final cleanup and update roadmap after merge.**

  ```bash
  git add macgit docs/superpowers/plans/2026-07-26-sidebar-view-refactor-roadmap.md
  git commit -m "refactor: complete SidebarView decomposition"
  ```

  After merging to `main`, mark Phase 4 `[completed]`. Confirm all roadmap phases are `[completed]` only when their implementation commits are present on `main`.
