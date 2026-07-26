# SidebarView Behavior-Preserving Refactor Design

## Goal

Reduce `macgit/Views/MainWindow/SidebarView.swift` from a 3,596-line mixed-responsibility view into focused SwiftUI components and orchestration extensions without changing visible behavior, Git behavior, or the initializer contract used by `MainWindowView`.

## Scope

This refactor covers:

- Sidebar models currently declared at the top of `SidebarView.swift`.
- Workspace, branches, worktrees, tags, remotes, stashes, submodules, and subtrees sections.
- Section headers, rows, context menus, drag/drop adapters, sheets, alerts, and loading orchestration.
- Existing sidebar-specific tests and final macOS build verification.

This refactor does not:

- Introduce a `SidebarViewModel`, `@Observable` state owner, or new persistence model.
- Change sidebar layout, labels, menus, gestures, loading policy, cache policy, or Git commands.
- Move repository-operation ownership from `MainWindowView` into section components.
- Add new sidebar features or redesign existing flows.
- Launch the application during verification.

## Current Problems

`SidebarView.swift` currently contains several independent concerns:

1. Shared selection, section, tree, confirmation, and worktree model types.
2. A large initializer with callbacks for every sidebar feature.
3. State for all eight sidebar sections and their presentation flows.
4. Section and row rendering.
5. Context-menu construction.
6. Drag-source, drop-target, payload, and hover handling.
7. Branch, remote, submodule, subtree, stash, and worktree loading.
8. Branch deletion, remote checkout/deletion, subtree unlinking, and the complete worktree-management workflow.
9. Five worktree sheets plus multiple alerts and presentation modifiers.

This makes narrow changes patch-fragile and makes it difficult to reason about whether a change affects only one section.

## Considered Approaches

### 1. Cross-file extensions only

Move methods into `SidebarView+*.swift` files while leaving all rendering as computed `some View` properties.

- Advantage: smallest mechanical diff.
- Disadvantage: the code remains one logical view with broad state access; it does not create reusable or independently understandable SwiftUI components.

### 2. Hybrid components plus orchestration extensions

Extract real `View` types for sections, rows, menus, and sheets. Keep repository lifecycle, state ownership, refresh fan-out, and Git orchestration in `SidebarView` and behavior-focused cross-file extensions.

- Advantage: meaningful component boundaries with low lifecycle risk.
- Advantage: preserves the current `SidebarView` initializer and `MainWindowView` callback seam.
- Disadvantage: cross-file extensions require selected shared members to use module-internal access rather than `private`.

This is the selected approach.

### 3. Observable state model

Move all state and loading into a new `@MainActor @Observable SidebarViewModel`.

- Advantage: strongest long-term separation between rendering and behavior.
- Disadvantage: changes state ownership, task lifetime, observation invalidation, and test architecture in the same change as the file split.

This is intentionally deferred until the component boundaries have stabilized.

## Architecture

### Root ownership

`SidebarView` remains the composition root and continues to own:

- `repositoryURL`, `selection`, environment dependencies, and the existing external callbacks.
- The current state lifetime for branch, tag, remote, stash, worktree, submodule, subtree, presentation, and drag/drop state.
- The repository-keyed `.task`, `.repositoryDidChange` subscription, visibility changes, and refresh fan-out.
- Global error presentation and repository-operation routing.

`MainWindowView` continues to present top-level application sheets and execute shared repository operations. `GitStatusService` remains the only home for Git process execution and discovery.

### Component boundaries

New components receive rendered values, bindings only where mutation is required, and narrowly grouped action closures. Components must not call Git services directly unless that exact operation already lives in the corresponding extracted `SidebarView` orchestration extension.

The external `SidebarView` initializer remains source-compatible. Internal action bundles adapt its existing callbacks to smaller component interfaces; `MainWindowView` does not need a callback API migration during this refactor.

### Target file map

Create the feature folder `macgit/Views/MainWindow/Sidebar/` and use these responsibilities:

- `SidebarSelection.swift`
  - Sidebar navigation selection.
- `SidebarItem.swift`
  - Workspace destinations and their icons.
- `SidebarSection.swift`
  - Sidebar section identity and workspace-item mapping.
- `BranchNode.swift`
  - Hierarchical branch/tag/remote tree node.
- `BranchRowItem.swift`
  - Flattened visible tree row.
- `DeleteConfirmationTarget.swift`
  - Local branch and branch-prefix deletion targets.
- `RemoteBranchDeleteTarget.swift`
  - Parsed remote branch deletion target.
- `WorktreeCreationMode.swift`
  - Existing-branch versus new-branch creation mode.
- `WorktreeHeaderAction.swift`
  - Worktree header menu actions.
- `SidebarSectionHeader.swift`
  - Shared section-header layout only.
  - Add/prune controls remain closure-driven and section-specific.
- `SidebarWorkspaceSection.swift`
  - Workspace navigation rows and Search callback.
- `SidebarBranchesSection.swift`
  - Branches section composition, loading/empty state, HEAD row, branch tree rows, and section drop target.
- `SidebarBranchRow.swift`
  - Folder/branch row interaction, selected-row tag, paired single/double-click gesture ownership, drag source, and current-branch drop target.
  - Reuse the existing `BranchRowContent` rendering.
- `SidebarBranchContextMenu.swift`
  - Local branch menu using rendered upstream/remote state plus callbacks.
- `SidebarFolderContextMenu.swift`
  - Branch-folder menu and prefix-deletion forwarding.
- `SidebarTagsSection.swift`
  - Tag section, tag rows, tag folder expansion, header drop target, and tag menu.
- `SidebarRemotesSection.swift`
  - Remote tree, row gestures, remote drag source, checkout forwarding, and remote context menu.
- `SidebarStashesSection.swift`
  - Stash rows, drag source, header drop target, and stash menu.
- `SidebarWorktreesSection.swift`
  - Worktree header, list rows, missing-item interception, and context menu.
- `SidebarWorktreePresentationModifier.swift`
  - Worktree alerts and sheet attachment without `AnyView` erasure.
- `WorktreeLabelSheet.swift`
- `WorktreeLockSheet.swift`
- `WorktreeMoveSheet.swift`
- `WorktreeCheckoutSheet.swift`
- `CreateWorktreeSheet.swift`
  - Each sheet owns rendering only and receives bindings/actions from `SidebarView`.
- `SidebarSubmodulesSection.swift`
  - Section loading/empty state and adaptation to the existing `SidebarSubmoduleRow`.
- `SidebarSubtreesSection.swift`
  - Section loading/empty state and adaptation to the existing `SidebarSubtreeRow`.
- `SidebarSubtreePresentationModifier.swift`
  - Edit/unlink presentation currently embedded in `SidebarView.swift`.

Keep behavior orchestration beside the root view:

- `SidebarView+Loading.swift`
  - Reset, initial load, force refresh, per-section load fan-out, branch/tag/remote/stash loading, tree flattening inputs, and branch sync loading.
- `SidebarView+DragDrop.swift`
  - Payload creation, item-provider loading, hover state, policy checks, and request forwarding.
- `SidebarView+BranchActions.swift`
  - Local branch deletion, prefix deletion, remote branch parsing, checkout, deletion, and branch-section expansion.
- `SidebarView+WorktreeActions.swift`
  - Worktree load, label, lock, unlock, prune, create, move, repair, checkout, and removal workflows.
- `SidebarView+SubmoduleActions.swift`
  - Submodule loading, confirmation decisions, and action forwarding.
- `SidebarView+SubtreeActions.swift`
  - Subtree loading and unlink workflow.

`SidebarBranchSyncBadgeResolver` remains a dedicated testable policy and moves to `SidebarBranchSyncBadgeResolver.swift`.

### Access control

Types and members used only inside one file remain `private`. Members shared between `SidebarView.swift` and its cross-file extensions become internal by omitting an access modifier. No shared seam becomes `public`.

The refactor must not use `fileprivate` for members needed by another file, because `fileprivate` does not cross Swift file boundaries.

### Data and event flow

The data flow remains:

1. `SidebarView` receives repository identity, selection binding, and callbacks from `MainWindowView`.
2. The repository-keyed task loads persisted section state and starts the existing section loaders.
3. Loaders call `GitStatusService`, then update the same state currently rendered by the sidebar.
4. Section components render value snapshots and bindings from the root.
5. Row/menu actions call narrow component closures.
6. Those closures update root presentation state, call an extracted `SidebarView` action, or forward to the existing `MainWindowView` callback.
7. Successful repository mutations preserve current refresh calls and `.repositoryDidChange` notifications.

No child section starts an independent repository lifecycle task in this refactor. This avoids duplicate loads and preserves the existing refresh ordering.

## Behavior Invariants

The implementation must preserve all of the following:

- The `SidebarView` initializer remains source-compatible with the current `MainWindowView` call site and preview.
- Workspace selection tags and Search behavior are unchanged.
- Section expansion state continues to use `SidebarSettingsStore`.
- The repository task remains keyed by repository path and the submodule visibility preference.
- `.repositoryDidChange` still force-refreshes the same sections for the matching repository.
- Submodule and subtree visibility preferences retain their existing lazy-loading behavior.
- Local branch single-click and simultaneous double-click remain attached to the same row that owns selected styling.
- Worktree missing-path handling still intercepts both selection and open actions.
- Remote branch and stash drag payloads retain their existing cleanup paths.
- Drop decisions continue to use `GitDragDropPolicy`; rejected remote drags keep their current silent behavior.
- Branch-list discovery continues to use the existing two-minute local cache and does not introduce an implicit network fetch.
- Context-menu labels, ordering, separators, disabled states, and destructive roles do not change.
- Worktree, submodule, and subtree confirmation copy does not change.
- Existing `MainWindowView` and `GitStatusService` ownership boundaries do not change.

## Migration Strategy

The refactor is divided into independently buildable phases:

1. Move shared models and pure leaf rendering types without changing call sites.
2. Extract workspace, branch, tag, remote, and stash components while preserving row gesture and drag/drop ownership.
3. Extract submodule and subtree sections and presentation.
4. Extract worktree section, sheets, alerts, and worktree action orchestration.
5. Move loading, branch, and drag/drop orchestration into cross-file extensions.
6. Remove obsolete computed `some View` helpers, `AnyView` erasure, and duplicated header wiring only after the extracted equivalents compile.
7. Run focused tests, build, inspect the diff, and confirm the original root view contains only composition and lifecycle responsibilities.

Each phase must compile before the next phase starts. Mechanical moves and cleanup should be separate commits so regressions can be located by commit boundary.

## Testing and Verification

Run focused tests for existing behavior seams:

- `SidebarTreeBuilderTests`
- `SidebarBranchSyncBadgeResolverTests`
- `SidebarViewStashTests`
- `GitDragDropPolicyTests`
- `GitDragDropBranchIntegrationTests`
- `WorktreeServiceTests`
- `WorktreeLabelStoreTests`
- `SubmoduleSidebarPolicyTests`
- `SubmoduleLifecyclePolicyTests`
- `SubtreeSidebarPolicyTests`

Add unit tests only if a pure policy or state transformation is newly extracted. Do not add screenshot tests merely to validate a mechanical file move.

After each major extraction phase, run the macOS build:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```

Do not launch the app. If test bootstrapping exits early with the documented `Early unexpected exit` or `abort() called` failure, do not rerun the same failing suite repeatedly; retain the successful build and report the exact test failure.

Final verification also includes:

```bash
git diff --check
git status --short
```

Every new Swift file must contain the repository AGPL v3 header.

## Success Criteria

- `SidebarView.swift` becomes a composition/lifecycle root rather than the implementation home for every section.
- Each extracted SwiftUI type has one clear responsibility and lives in its own Swift file.
- No initializer call-site migration is required in `MainWindowView`.
- No Git command, cache policy, menu action, confirmation, selection, gesture, or drag/drop behavior changes.
- Focused tests pass unless blocked by the documented test-host bootstrap failure.
- The macOS project build succeeds without launching the application.
