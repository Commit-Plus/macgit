# SidebarView Refactor Phase 1 Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move shared sidebar types and pure foundational views out of `SidebarView.swift` without changing feature rendering or behavior.

**Architecture:** Create the `Views/MainWindow/Sidebar/` feature folder, place every moved type in its own Swift file, and preserve existing names so current call sites continue to compile. Extract only the shared section-header rendering and workspace section in this phase; repository state and Git behavior stay in `SidebarView`.

**Tech Stack:** Swift 5 language mode, SwiftUI, macOS 26.2, XCTest, existing Xcode synchronized file groups.

## Global Constraints

- Start from clean `main` on branch `codex/sidebar-refactor-phase-1-foundation`.
- Preserve all type names, enum cases, raw values, IDs, labels, icons, and access levels required by current callers.
- Do not change `SidebarView` external initializer or `MainWindowView`.
- Do not move loading, drag/drop, context menus, or Git calls in this phase.
- Every new Swift file includes the AGPL v3 header.
- Do not launch the app.

---

### Task 1: Move navigation and section identity types

**Files:**
- Create: `macgit/Views/MainWindow/Sidebar/SidebarSelection.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarItem.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarSection.swift`
- Modify: `macgit/Views/MainWindow/SidebarView.swift:29-77`

**Interfaces:**
- Produces the existing `enum SidebarSelection: Hashable`.
- Produces the existing `enum SidebarItem: String, CaseIterable, Identifiable`.
- Produces the existing `enum SidebarSection: String, CaseIterable`.
- All names, cases, raw values, `id`, `icon`, and `items` behavior remain byte-for-byte equivalent.

- [ ] **Step 1: Record the current declarations and consumers.**

  Run:

  ```bash
  rg -n 'SidebarSelection|SidebarItem|SidebarSection' macgit macgitTests
  ```

  Confirm that `MainWindowView`, `SidebarSettingsStore`, tests, and sidebar rows use the unqualified type names.

- [ ] **Step 2: Move each declaration into its named file.**

  Copy the existing declaration without renaming cases or changing implementation. Each file must begin with the AGPL header and import only what it needs:

  ```swift
  import Foundation

  enum SidebarSelection: Hashable {
      case item(SidebarItem)
      case branch(String)
      case worktree(URL)
      case tag(String)
      case remoteBranch(String)
      case stash(String)
      case head(String)
      case submodule(String)
      case subtree(String)
  }
  ```

  `SidebarItem.swift` and `SidebarSection.swift` retain their current bodies exactly.

- [ ] **Step 3: Remove the original declarations and build.**

  Run:

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  ```

  Expected: `BUILD SUCCEEDED` with no duplicate or missing type errors.

- [ ] **Step 4: Commit the navigation type move.**

  ```bash
  git add macgit/Views/MainWindow/Sidebar macgit/Views/MainWindow/SidebarView.swift
  git commit -m "refactor: move sidebar navigation types"
  ```

### Task 2: Move tree and confirmation models

**Files:**
- Create: `macgit/Views/MainWindow/Sidebar/BranchNode.swift`
- Create: `macgit/Views/MainWindow/Sidebar/BranchRowItem.swift`
- Create: `macgit/Views/MainWindow/Sidebar/DeleteConfirmationTarget.swift`
- Create: `macgit/Views/MainWindow/Sidebar/RemoteBranchDeleteTarget.swift`
- Create: `macgit/Views/MainWindow/Sidebar/WorktreeCreationMode.swift`
- Create: `macgit/Views/MainWindow/Sidebar/WorktreeHeaderAction.swift`
- Modify: `macgit/Views/MainWindow/SidebarView.swift:79-122`

**Interfaces:**
- Preserve every stored property, conformance, generated ID, and computed `id`/`fullPath`.
- `SidebarTreeBuilder` and `BranchRowContent` continue using `BranchNode` and `BranchRowItem` without qualification.

- [ ] **Step 1: Run the existing tree tests before moving types.**

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/SidebarTreeBuilderTests test
  ```

  Expected: PASS. If test-host bootstrapping aborts, record the exact output and continue with build verification.

- [ ] **Step 2: Move one model per file.**

  Preserve implementations exactly. For example:

  ```swift
  import Foundation

  struct BranchRowItem: Identifiable, Equatable {
      let id: UUID
      let name: String
      let fullPath: String
      let isFolder: Bool
      let indent: Int
  }
  ```

  Use `Foundation` for `UUID`/`URL`; no model file imports SwiftUI.

- [ ] **Step 3: Remove the original model declarations and rerun tests/build.**

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/SidebarTreeBuilderTests test
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  ```

- [ ] **Step 4: Commit the model move.**

  ```bash
  git add macgit/Views/MainWindow/Sidebar macgit/Views/MainWindow/SidebarView.swift
  git commit -m "refactor: move sidebar tree models"
  ```

### Task 3: Move the branch sync resolver

**Files:**
- Create: `macgit/Views/MainWindow/Sidebar/SidebarBranchSyncBadgeResolver.swift`
- Modify: `macgit/Views/MainWindow/SidebarView.swift:124-137`
- Test: `macgitTests/SidebarBranchSyncBadgeResolverTests.swift`

**Interfaces:**
- Produces the unchanged static signature:

  ```swift
  static func status(
      for branch: String,
      currentBranch: String,
      branchSyncStatus: [String: BranchSyncStatus],
      currentBranchFallbackSyncStatus: BranchSyncStatus?
  ) -> BranchSyncStatus?
  ```

- [ ] **Step 1: Run the resolver tests before the move.**

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/SidebarBranchSyncBadgeResolverTests test
  ```

- [ ] **Step 2: Move the resolver without logic changes.**

  Keep current-branch fallback precedence and cached non-current status behavior unchanged.

- [ ] **Step 3: Rerun the focused tests and commit.**

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/SidebarBranchSyncBadgeResolverTests test
  git add macgit/Views/MainWindow/Sidebar/SidebarBranchSyncBadgeResolver.swift macgit/Views/MainWindow/SidebarView.swift
  git commit -m "refactor: isolate sidebar branch sync resolver"
  ```

### Task 4: Extract the shared section header

**Files:**
- Create: `macgit/Views/MainWindow/Sidebar/SidebarSectionHeader.swift`
- Modify: `macgit/Views/MainWindow/SidebarView.swift:1121-1192`

**Interfaces:**
- Produces:

  ```swift
  struct SidebarSectionHeader<Trailing: View>: View {
      let section: SidebarSection
      let isExpanded: Bool
      let activeDropLabel: String?
      let onToggle: () -> Void
      @ViewBuilder let trailing: Trailing
  }
  ```

- The view renders the existing uppercase title, optional drop-label capsule, caller-supplied trailing controls, chevron, padding, content shape, and tap handler.

- [ ] **Step 1: Create the generic header component.**

  Implement the current visual body exactly:

  ```swift
  HStack {
      Text(section.rawValue)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)
      Spacer()
      if let activeDropLabel {
          Text(activeDropLabel)
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(Color.accentColor)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Color.accentColor.opacity(0.12), in: Capsule())
      }
      trailing
      Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(.secondary)
          .padding(.trailing, 8)
  }
  .contentShape(Rectangle())
  .onTapGesture(perform: onToggle)
  ```

- [ ] **Step 2: Replace `sectionHeaderContent` with the component.**

  At each current call site, pass the existing active drop label and trailing controls. Keep worktree, submodule, and subtree buttons in `SidebarView` closures during this phase.

- [ ] **Step 3: Build and inspect the diff for copy/layout changes.**

  ```bash
  git diff --word-diff -- macgit/Views/MainWindow/SidebarView.swift
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  ```

  Confirm fonts, padding, chevron, button labels, help text, and menu labels are unchanged.

- [ ] **Step 4: Commit the header component.**

  ```bash
  git add macgit/Views/MainWindow/Sidebar/SidebarSectionHeader.swift macgit/Views/MainWindow/SidebarView.swift
  git commit -m "refactor: extract sidebar section header"
  ```

### Task 5: Extract the workspace section and finish Phase 1

**Files:**
- Create: `macgit/Views/MainWindow/Sidebar/SidebarWorkspaceSection.swift`
- Modify: `macgit/Views/MainWindow/SidebarView.swift:653-668`
- Modify: `docs/superpowers/plans/2026-07-26-sidebar-view-refactor-roadmap.md`

**Interfaces:**
- Produces:

  ```swift
  struct SidebarWorkspaceSection: View {
      let onRequestSearch: () -> Void
  }
  ```

- Navigation rows retain their existing `SidebarSelection.item(item)` tags. Search remains an action row without becoming the selected list destination.

- [ ] **Step 1: Extract the existing workspace section body.**

  Move the current `Section(SidebarSection.workspace.rawValue)` rendering into `SidebarWorkspaceSection`. Pass `onRequestSearch` directly to its search tap gesture.

- [ ] **Step 2: Replace the original section and run focused tests/build.**

  ```bash
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/SidebarViewStashTests -only-testing:macgitTests/SidebarTreeBuilderTests -only-testing:macgitTests/SidebarBranchSyncBadgeResolverTests test
  xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  ```

- [ ] **Step 3: Verify file headers and diff hygiene.**

  ```bash
  rg -L 'GNU Affero General Public License' macgit/Views/MainWindow/Sidebar --glob '*.swift'
  git diff --check
  git status --short
  ```

  Expected: `rg -L` prints no Swift file and `git diff --check` prints nothing.

- [ ] **Step 4: Mark Phase 1 completed only after merge.**

  Commit implementation first:

  ```bash
  git add macgit docs/superpowers/plans/2026-07-26-sidebar-view-refactor-roadmap.md
  git commit -m "refactor: extract sidebar workspace foundation"
  ```

  After the phase branch is merged to `main`, change the roadmap Phase 1 status from `[pending]` to `[completed]` in the merge/status commit. Do not mark later phases in progress until their branch is created from updated clean `main`.
