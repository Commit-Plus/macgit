# SidebarView Refactor Phase 2 Core Sections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract branches, tags, remotes, and stashes into real SwiftUI section/row/menu components while preserving selection, gestures, drag/drop, menu behavior, and root-owned state.

**Architecture:** `SidebarView` continues owning all state and repository lifecycle. Each section receives immutable rendering state plus one feature-specific action bundle. Drag/drop policy and payload mutation remain closures backed by `SidebarView`; components only attach the same AppKit/SwiftUI interaction surfaces.

**Tech Stack:** SwiftUI, AppKit `NSItemProvider`/`NSPasteboard`, Uniform Type Identifiers, existing Git drag/drop policy, XCTest.

## Global Constraints

- Start from clean Phase-1-updated `main` on branch `codex/sidebar-refactor-phase-2-core-sections`.
- Do not change `SidebarView` external initializer, repository tasks, notification handling, service calls, or cache behavior.
- Paired local-branch single/double-click gestures stay on the row that owns selected styling.
- Preserve every menu label, order, separator, disabled condition, role, and drag cleanup path.
- Every new Swift file includes the AGPL v3 header.
- Do not launch the app.

---

### Task 1: Define core-section action bundles

**Files:**
- Create: `macgit/Views/MainWindow/Sidebar/SidebarBranchSectionActions.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarTagSectionActions.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarRemoteSectionActions.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarStashSectionActions.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarDropActions.swift`
- Modify: `macgit/Views/MainWindow/SidebarView.swift`

**Interfaces:**
- `SidebarDropActions` produces:

  ```swift
  struct SidebarDropActions {
      let activePayload: () -> GitDragPayload?
      let canAccept: (GitDragPayload, GitDragTarget, Bool) -> Bool
      let handlePayload: (GitDragPayload, GitDragTarget, Bool) -> Void
      let handleProviders: ([NSItemProvider], GitDragTarget, Bool) -> Bool
      let clearPayload: (GitDragPayload?) -> Void
  }
  ```

- `SidebarBranchSectionActions` groups section toggle, folder toggle, selection, checkout, all existing branch-menu callbacks, deletion confirmation, item-provider creation, current-target hover, and `SidebarDropActions`.
- Tag, remote, and stash bundles group only callbacks used by their section.

- [ ] **Step 1: Add the action bundle value types.**

  Use non-escaping stored closures with exact domain values. The branch bundle must include:

  ```swift
  struct SidebarBranchSectionActions {
      let toggleSection: () -> Void
      let toggleFolder: (String) -> Void
      let select: (SidebarSelection) -> Void
      let checkout: (String) -> Void
      let fetch: (String) -> Void
      let pullTracked: (String) -> Void
      let pushTracked: (String) -> Void
      let rename: (String) -> Void
      let createPullRequest: (String) -> Void
      let createBranchFrom: (String) -> Void
      let createTagFrom: (String) -> Void
      let rebaseOnto: (String) -> Void
      let mergeIntoCurrent: (String) -> Void
      let pushToRemote: (String, String) -> Void
      let trackRemoteBranch: (String, String?) -> Void
      let confirmDelete: (DeleteConfirmationTarget) -> Void
      let makeItemProvider: (String) -> NSItemProvider
      let setHeaderDropTargeted: (Bool) -> Void
      let setCurrentDropTargeted: (Bool) -> Void
      let currentDropLabel: () -> String
      let drop: SidebarDropActions
  }
  ```

  Define the remaining bundles exactly:

  ```swift
  struct SidebarTagSectionActions {
      let toggleSection: () -> Void
      let toggleFolder: (String) -> Void
      let select: (SidebarSelection) -> Void
      let checkout: (String) -> Void
      let showDetails: (String) -> Void
      let diffAgainstCurrent: (String) -> Void
      let pushToRemote: (String, String) -> Void
      let delete: (String) -> Void
      let setHeaderDropTargeted: (Bool) -> Void
      let drop: SidebarDropActions
  }

  struct SidebarRemoteSectionActions {
      let toggleSection: () -> Void
      let toggleFolder: (String) -> Void
      let select: (SidebarSelection) -> Void
      let checkout: (String) -> Void
      let pullIntoCurrent: (String, String) -> Void
      let confirmDelete: (RemoteBranchDeleteTarget) -> Void
      let createPullRequest: (String, String) -> Void
      let makePayload: (String) -> GitDragPayload
      let finishDrag: (String) -> Void
      let setHeaderDropTargeted: (Bool) -> Void
      let drop: SidebarDropActions
  }

  struct SidebarStashSectionActions {
      let toggleSection: () -> Void
      let select: (SidebarSelection) -> Void
      let apply: (String) -> Void
      let delete: (String) -> Void
      let makeItemProvider: (String) -> NSItemProvider
      let setHeaderDropTargeted: (Bool) -> Void
      let drop: SidebarDropActions
  }
  ```

- [ ] **Step 2: Add internal computed adapters in `SidebarView`.**

  Create `branchSectionActions`, `tagSectionActions`, `remoteSectionActions`, and `stashSectionActions` that forward to the current methods and callback properties. Do not alter the external initializer.

- [ ] **Step 3: Build before rendering uses the bundles.**

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  ```

- [ ] **Step 4: Commit the interface foundation.**

  ```bash
  git add macgit/Views/MainWindow/Sidebar macgit/Views/MainWindow/SidebarView.swift
  git commit -m "refactor: add sidebar section action interfaces"
  ```

### Task 2: Extract branch menus

**Files:**
- Create: `macgit/Views/MainWindow/Sidebar/SidebarBranchContextMenu.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarFolderContextMenu.swift`
- Modify: `macgit/Views/MainWindow/SidebarView.swift:2147-2287`

**Interfaces:**
- `SidebarBranchContextMenu` receives `branch`, `currentBranch`, `syncStatus`, `upstream`, `remoteNames`, `branchesByRemote`, and `SidebarBranchSectionActions`.
- `SidebarFolderContextMenu` receives `prefix`, `deletableBranches`, and `SidebarBranchSectionActions`.

- [ ] **Step 1: Extract the local branch menu exactly.**

  Preserve the current order:

  ```text
  Checkout
  Merge / Rebase
  Fetch / Pull tracked / Push tracked / Push to / Track Remote Branch
  Create Branch / Create Tag
  Diff Against Current (disabled)
  Rename / Delete
  Copy Branch Name
  Create Pull Request
  ```

  Keep `BranchFetchActionPolicy` and `BranchUpstreamActionPolicy` disabled-state decisions unchanged.

- [ ] **Step 2: Extract the folder context menu.**

  Pass the already calculated deletable branch list so the menu does not need access to the root tree:

  ```swift
  SidebarFolderContextMenu(
      prefix: row.fullPath,
      deletableBranches: branchesUnderPrefix(row.fullPath).filter { $0 != currentBranch },
      actions: actions
  )
  ```

- [ ] **Step 3: Replace original menu builders and build.**

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  git diff --word-diff -- macgit/Views/MainWindow/SidebarView.swift macgit/Views/MainWindow/Sidebar
  ```

- [ ] **Step 4: Commit branch menu extraction.**

  ```bash
  git add macgit/Views/MainWindow
  git commit -m "refactor: extract sidebar branch menus"
  ```

### Task 3: Extract branch row and branches section

**Files:**
- Create: `macgit/Views/MainWindow/Sidebar/SidebarBranchRow.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarBranchesSection.swift`
- Modify: `macgit/Views/MainWindow/BranchRowView.swift`
- Modify: `macgit/Views/MainWindow/SidebarView.swift:670-693,868-927,1540-1707`
- Test: `macgitTests/SidebarBranchSyncBadgeResolverTests.swift`
- Test: `macgitTests/GitDragDropPolicyTests.swift`
- Test: `macgitTests/GitDragDropBranchIntegrationTests.swift`

**Interfaces:**
- `SidebarBranchRow` receives one `BranchRowItem`, current-branch rendering inputs, menu inputs, and `SidebarBranchSectionActions`.
- `SidebarBranchesSection` receives branch nodes flattened by the root, loading/current-HEAD state, expanded folders, sync data, header drop state, and actions.
- `BranchRowContent` remains pure rendering and is reused.

- [ ] **Step 1: Move complete row interaction ownership into `SidebarBranchRow`.**

  Preserve this gesture shape for leaf rows:

  ```swift
  content
      .tag(SidebarSelection.branch(row.fullPath))
      .onTapGesture {
          actions.select(.branch(row.fullPath))
      }
      .simultaneousGesture(
          TapGesture(count: 2).onEnded {
              if !isCurrentBranch {
                  actions.checkout(row.fullPath)
              }
          }
      )
  ```

  The selected tag, content background, both gestures, context menu, drag source, and current-branch drop overlay remain on this same extracted view.

- [ ] **Step 2: Extract the branches section and real-row drop header.**

  Move loading, empty state, detached HEAD row, `ForEach`, `RemoteBranchCheckoutDropZone`, `SidebarBranchDropTarget`, and fallback `.onDrop` wiring together. Keep the current payload rejection and cleanup order.

- [ ] **Step 3: Replace original branch rendering and run focused tests.**

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/SidebarBranchSyncBadgeResolverTests -only-testing:macgitTests/GitDragDropPolicyTests -only-testing:macgitTests/GitDragDropBranchIntegrationTests test
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  ```

- [ ] **Step 4: Commit branch component extraction.**

  ```bash
  git add macgit/Views/MainWindow macgitTests
  git commit -m "refactor: extract sidebar branches section"
  ```

### Task 4: Extract tags and remotes

**Files:**
- Create: `macgit/Views/MainWindow/Sidebar/SidebarTagsSection.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarTagRow.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarTagContextMenu.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarRemotesSection.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarRemoteRow.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarRemoteContextMenu.swift`
- Modify: `macgit/Views/MainWindow/SidebarView.swift:716-756,929-1021,1763-1932,2001-2139`

**Interfaces:**
- Tag section consumes visible rows, expansion state, remotes, loading/drop state, and `SidebarTagSectionActions`.
- Remote section consumes visible rows, expansion/current-branch state, loading/drop state, and `SidebarRemoteSectionActions`.
- Root retains `checkoutRemoteBranch` and `deleteRemoteBranch`; components invoke closures only.

- [ ] **Step 1: Extract tag row, menu, and section.**

  Preserve folder toggling, tag selection, double-click checkout, clipboard behavior, push remote ordering, and delete forwarding. Preserve the tag-header drop target and fallback provider path.

- [ ] **Step 2: Extract remote row, menu, and section.**

  Keep `origin/HEAD` non-draggable, retain `SidebarRemoteBranchDragSource` for normal branches, and preserve double-click selection before checkout forwarding.

- [ ] **Step 3: Build and compare menu strings.**

  ```bash
  rg -n 'Checkout|Copy Tag Name|Diff Against Current|Delete Remote Branch|Create Pull Request' macgit/Views/MainWindow/Sidebar
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  ```

- [ ] **Step 4: Commit tag/remote extraction.**

  ```bash
  git add macgit/Views/MainWindow
  git commit -m "refactor: extract sidebar tag and remote sections"
  ```

### Task 5: Extract stashes and finish Phase 2

**Files:**
- Create: `macgit/Views/MainWindow/Sidebar/SidebarStashesSection.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarStashRow.swift`
- Modify: `macgit/Views/MainWindow/SidebarView.swift:758-777,1074-1119,1933-1989`
- Modify: `docs/superpowers/plans/2026-07-26-sidebar-view-refactor-roadmap.md`
- Test: `macgitTests/SidebarViewStashTests.swift`
- Test: `macgitTests/GitDragDropPolicyTests.swift`

**Interfaces:**
- Stash rows retain selection, double-click apply, transfer payload, `StashDragPreview`, Apply menu, and destructive Delete menu.
- Stash section retains its real-row drop header and file-count hover label.

- [ ] **Step 1: Extract the stash row and section.**

  Keep the current drag provider registration:

  ```swift
  provider.registerDataRepresentation(
      forTypeIdentifier: UTType.macgitGitDragPayload.identifier,
      visibility: .all
  ) { completionHandler in
      completionHandler(data, nil)
      return nil
  }
  ```

- [ ] **Step 2: Remove obsolete core-section view builders and run verification.**

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/SidebarViewStashTests -only-testing:macgitTests/GitDragDropPolicyTests test
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  git diff --check
  ```

- [ ] **Step 3: Verify row gesture ownership.**

  Run:

  ```bash
  rg -n 'simultaneousGesture|onTapGesture\\(count: 2\\)|SidebarBranchDropTarget|SidebarRemoteBranchDragSource' macgit/Views/MainWindow/Sidebar
  ```

  Confirm local branch paired gestures remain in `SidebarBranchRow`, remote paired actions remain in `SidebarRemoteRow`, and stash double-click remains in `SidebarStashRow`.

- [ ] **Step 4: Commit and update roadmap after merge.**

  ```bash
  git add macgit docs/superpowers/plans/2026-07-26-sidebar-view-refactor-roadmap.md
  git commit -m "refactor: extract sidebar stashes section"
  ```

  After merging to `main`, mark Phase 2 `[completed]`.
