# SidebarView Refactor Phase 3 Specialized Sections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract worktree, submodule, and subtree sections plus their sheets and alerts into focused SwiftUI components while retaining root-owned state and existing operation seams.

**Architecture:** Specialized sections render values and forward actions. `SidebarView` still owns all presentation bindings and async methods during this phase. Dedicated sheet views receive bindings and action closures; presentation modifiers instantiate concrete views directly so the current `AnyView` erasure can be removed safely.

**Tech Stack:** SwiftUI, AppKit `NSOpenPanel`, existing `GitStatusService` worktree/submodule/subtree APIs, XCTest.

## Global Constraints

- Start from clean Phase-2-updated `main` on branch `codex/sidebar-refactor-phase-3-specialized-sections`.
- Preserve worktree missing-path interception, force confirmations, copy, button labels, disabled states, and sheet keyboard shortcuts.
- Preserve submodule/subtree policy decisions and `MainWindowView` callback ownership.
- Do not move async methods into cross-file extensions until Phase 4.
- Every new Swift file includes the AGPL v3 header.
- Do not launch the app.

---

### Task 1: Extract submodule section and action adapter

**Files:**
- Create: `macgit/Views/MainWindow/Sidebar/SidebarSubmoduleSectionActions.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarSubmodulesSection.swift`
- Modify: `macgit/Views/MainWindow/SidebarView.swift:779-829,1023-1072`
- Test: `macgitTests/SubmoduleSidebarPolicyTests.swift`
- Test: `macgitTests/SubmoduleLifecyclePolicyTests.swift`

**Interfaces:**
- `SidebarSubmoduleSectionActions` contains section toggle, open/show/terminal, initialize, both update modes, synchronize URL, edit, deinitialize, and remove callbacks.
- `SidebarSubmodulesSection` receives `repositoryURL`, entries, expanded/loading state, header add action, and `SidebarSubmoduleSectionActions`.
- It continues adapting each entry to the existing `SidebarSubmoduleRow`.

- [ ] **Step 1: Add the submodule action bundle.**

  ```swift
  struct SidebarSubmoduleSectionActions {
      let toggleSection: () -> Void
      let open: (URL) -> Void
      let showInFinder: (URL) -> Void
      let openInTerminal: (URL) -> Void
      let initialize: (String) -> Void
      let update: (String, SubmoduleUpdateMode) -> Void
      let synchronizeURL: (String) -> Void
      let edit: (GitSubmoduleEntry) -> Void
      let deinitialize: (GitSubmoduleEntry) -> Void
      let remove: (GitSubmoduleEntry) -> Void
  }
  ```

  Root adapters call the same callbacks and confirmation methods currently used by `submoduleRow`.

- [ ] **Step 2: Extract the section and row adaptation.**

  Preserve `repositoryURL.appendingPathComponent(entry.path, isDirectory: true)`, the existing loading/empty rows, `.tag(SidebarSelection.submodule(entry.path))`, and Add Submodule header button.

- [ ] **Step 3: Run focused tests and build.**

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/SubmoduleSidebarPolicyTests -only-testing:macgitTests/SubmoduleLifecyclePolicyTests test
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  ```

- [ ] **Step 4: Commit submodule extraction.**

  ```bash
  git add macgit/Views/MainWindow
  git commit -m "refactor: extract sidebar submodules section"
  ```

### Task 2: Extract subtree section and presentation modifier

**Files:**
- Create: `macgit/Views/MainWindow/Sidebar/SidebarSubtreeSectionActions.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarSubtreesSection.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarSubtreePresentationModifier.swift`
- Modify: `macgit/Views/MainWindow/SidebarView.swift:228-263,831-866,632-650`
- Test: `macgitTests/SubtreeSidebarPolicyTests.swift`

**Interfaces:**
- `SidebarSubtreeSectionActions` groups section toggle, Finder, Terminal, Pull, Push, Edit, and Unlink actions.
- `SidebarSubtreePresentationModifier` receives bindings to `subtreeToEdit` and `subtreeToUnlink`, update/unlink callbacks, and `RepositoryOperationRunner`.
- The modifier constructs `EditSubtreeSheet` directly and does not return `AnyView`.

- [ ] **Step 1: Extract subtree action bundle and section.**

  Define:

  ```swift
  struct SidebarSubtreeSectionActions {
      let toggleSection: () -> Void
      let showInFinder: (URL) -> Void
      let openInTerminal: (URL) -> Void
      let pull: (GitSubtreeEntry) -> Void
      let push: (GitSubtreeEntry) -> Void
      let edit: (GitSubtreeEntry) -> Void
      let unlink: (GitSubtreeEntry) -> Void
  }
  ```

  Preserve row path construction, `SidebarSubtreeRow`, `.tag(SidebarSelection.subtree(entry.id))`, loading/empty rendering, and Add/Link Subtree header action.

- [ ] **Step 2: Extract the concrete presentation modifier.**

  Keep the current unlink binding behavior:

  ```swift
  Binding(
      get: { subtreeToUnlink != nil },
      set: { isPresented in
          if !isPresented {
              subtreeToUnlink = nil
          }
      }
  )
  ```

  Preserve the exact message that unlink removes Commit+ metadata but leaves files unchanged.

- [ ] **Step 3: Replace `SubtreePresentationModifier` and build/test.**

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/SubtreeSidebarPolicyTests test
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  ```

- [ ] **Step 4: Commit subtree extraction.**

  ```bash
  git add macgit/Views/MainWindow
  git commit -m "refactor: extract sidebar subtrees section"
  ```

### Task 3: Extract worktree sheet views

**Files:**
- Create: `macgit/Views/MainWindow/Sidebar/WorktreeLabelSheet.swift`
- Create: `macgit/Views/MainWindow/Sidebar/WorktreeLockSheet.swift`
- Create: `macgit/Views/MainWindow/Sidebar/WorktreeMoveSheet.swift`
- Create: `macgit/Views/MainWindow/Sidebar/WorktreeCheckoutSheet.swift`
- Create: `macgit/Views/MainWindow/Sidebar/CreateWorktreeSheet.swift`
- Modify: `macgit/Views/MainWindow/SidebarView.swift:2353-2507,2615-2783`

**Interfaces:**
- `WorktreeLabelSheet` receives `entry`, `Binding<String> label`, Cancel, and Save.
- `WorktreeLockSheet` receives `entry`, `Binding<String> reason`, `isUpdating`, Cancel, and Lock.
- `WorktreeMoveSheet` receives `entry`, `Binding<String> path`, error, `canMove`, `isMoving`, Cancel, and Move.
- `WorktreeCheckoutSheet` receives `entry`, branch options, `Binding<String> selection`, error, `canCheckout`, `isCheckingOut`, Cancel, and Checkout.
- `CreateWorktreeSheet` receives all current creation bindings, validation state, loading/error state, and Cancel/Create actions.

- [ ] **Step 1: Extract label, lock, and move sheets.**

  Preserve the existing title, path display, text-field labels, dimensions, Cancel/default keyboard shortcuts, and disabled states. Button callbacks contain no Git calls:

  ```swift
  Button("Save", action: onSave)
      .keyboardShortcut(.defaultAction)
  ```

- [ ] **Step 2: Extract checkout and create sheets.**

  Keep the current picker values, creation modes, custom-path behavior, error placement, open-after-create toggle, and form dimensions. The root remains responsible for path suggestion and validation.

- [ ] **Step 3: Replace computed `some View` sheet builders.**

  Instantiate concrete sheet types with existing bindings and closures. Do not change state reset timing on Cancel or successful completion.

- [ ] **Step 4: Build and commit sheet extraction.**

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  git add macgit/Views/MainWindow
  git commit -m "refactor: extract sidebar worktree sheets"
  ```

### Task 4: Extract worktree section, menu, and presentation

**Files:**
- Create: `macgit/Views/MainWindow/Sidebar/SidebarWorktreeSectionActions.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarWorktreesSection.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarWorktreeRow.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarWorktreeContextMenu.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarWorktreePresentationModifier.swift`
- Modify: `macgit/Views/MainWindow/SidebarView.swift:139-226,695-714,1148-1170,1490-1538,1709-1760,2289-2351`
- Test: `macgitTests/WorktreeServiceTests.swift`
- Test: `macgitTests/WorktreeLabelStoreTests.swift`

**Interfaces:**
- `SidebarWorktreeSectionActions` groups section toggle, create/prune preparation, select/open/terminal, label, lock/unlock, move, switch, and remove actions.
- `SidebarWorktreeRow` owns both tap and double-tap missing-path interception through root-provided callbacks.
- `SidebarWorktreePresentationModifier` attaches all current worktree alerts and the five concrete sheet views.

- [ ] **Step 1: Add the worktree action bundle.**

  ```swift
  struct SidebarWorktreeSectionActions {
      let toggleSection: () -> Void
      let prepareCreate: () -> Void
      let confirmPrune: () -> Void
      let select: (WorktreeEntry) -> Void
      let open: (WorktreeEntry) -> Void
      let openInTerminal: (URL) -> Void
      let editLabel: (WorktreeEntry) -> Void
      let clearLabel: (WorktreeEntry) -> Void
      let editLock: (WorktreeEntry) -> Void
      let unlock: (WorktreeEntry) -> Void
      let move: (WorktreeEntry) -> Void
      let switchBranch: (WorktreeEntry) -> Void
      let confirmRemoval: (WorktreeEntry) -> Void
  }
  ```

- [ ] **Step 2: Extract row and context menu.**

  Preserve icon selection, `(this)` marker, dirty count, missing `?`, both gestures, and every menu boundary. `SidebarWorktreeRow` must call root `select(entry)` and `open(entry)` so the existing missing-path revalidation remains authoritative.

- [ ] **Step 3: Extract section header and rows.**

  Keep Create Worktree and Worktree Actions controls, semantic tint, loading/empty state, and current ordering.

- [ ] **Step 4: Extract concrete worktree presentation.**

  Replace closure-returned `AnyView` values with direct sheet construction. Preserve alert titles, destructive roles, force wording, operation labels, and state cleanup.

- [ ] **Step 5: Run focused tests/build and commit.**

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/WorktreeServiceTests -only-testing:macgitTests/WorktreeLabelStoreTests test
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  git add macgit/Views/MainWindow macgitTests
  git commit -m "refactor: extract sidebar worktrees section"
  ```

### Task 5: Remove specialized inline rendering and finish Phase 3

**Files:**
- Modify: `macgit/Views/MainWindow/SidebarView.swift`
- Modify: `docs/superpowers/plans/2026-07-26-sidebar-view-refactor-roadmap.md`

**Interfaces:**
- `sidebarRows` composes the extracted specialized section types.
- `sidebarContent` attaches concrete subtree, submodule, and worktree presentation modifiers.
- No `AnyView` remains in sidebar presentation.

- [ ] **Step 1: Remove obsolete helpers and scan ownership.**

  ```bash
  rg -n 'AnyView|submoduleRow|subtreeRow|worktreeRowView|worktreeLabelSheet|worktreeLockSheet|worktreeMoveSheet|worktreeCheckoutSheet|createWorktreeSheet' macgit/Views/MainWindow/SidebarView.swift
  ```

  Expected: no obsolete rendering helper or `AnyView` match remains; action method names may remain for Phase 4.

- [ ] **Step 2: Run the specialized focused suite and build.**

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/WorktreeServiceTests -only-testing:macgitTests/WorktreeLabelStoreTests -only-testing:macgitTests/SubmoduleSidebarPolicyTests -only-testing:macgitTests/SubmoduleLifecyclePolicyTests -only-testing:macgitTests/SubtreeSidebarPolicyTests test
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  git diff --check
  ```

- [ ] **Step 3: Commit and update roadmap after merge.**

  ```bash
  git add macgit docs/superpowers/plans/2026-07-26-sidebar-view-refactor-roadmap.md
  git commit -m "refactor: finish specialized sidebar extraction"
  ```

  After merging to `main`, mark Phase 3 `[completed]`.
