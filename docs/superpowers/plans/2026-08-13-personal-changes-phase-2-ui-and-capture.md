# Personal Changes Phase 2: UI, Capture, and Profile Management

**Branch:** `codex/personal-changes-phase-2-ui-and-capture`

**Goal:** Expose Phase 1 through a dedicated Sidebar section and detail surface, and let users create profiles from eligible File Status files, hunks, and lines while keeping managed changes visible as normal Git changes.

**Architecture:** A repository-scoped `PersonalChangesController` is the single observable source for profiles and derived current-worktree state. `MainWindowView` owns the controller and coordinates sheets/operations. Sidebar, detail, File Status, and Diff views render state and emit typed immutable requests. Personal Change menus are shared between ellipsis and right-click surfaces.

## Prerequisites

- Phase 1 is merged to `main` and the Phase 1 roadmap row is `[completed]`.
- Start from clean, updated `main` and create the Phase 2 branch.
- Re-run the Phase 1 lifecycle integration tests before UI integration.
- Confirm current `SidebarView` section order and both File Status menu implementations before editing.

## Tasks

### Task 1: Add the repository-scoped controller

**Files:**

- Create: `macgit/App/PersonalChangesController.swift`
- Modify: `macgit/Views/MainWindow/MainWindowView.swift`
- Test: `macgitTests/PersonalChangesControllerTests.swift`

- [ ] Load profiles and inspect their state for the current repository/working copy.
- [ ] Expose loading, profile issues, derived state, and mutation-in-progress state without duplicating service logic.
- [ ] Reload on matching `.repositoryDidChange`, current-branch changes, and app activation without causing mutations.
- [ ] Cancel or ignore stale async results when repository identity changes.
- [ ] Build immutable Sendable requests before starting Tasks.
- [ ] Keep errors visible while successful routine operations remain silent.
- [ ] Test repository switching, stale-result suppression, corrupt-profile isolation, and refresh after Capture/Apply/Pause.

### Task 2: Add the Sidebar section and selection route

**Files:**

- Modify: `macgit/Views/MainWindow/Sidebar/SidebarSection.swift`
- Modify: `macgit/Views/MainWindow/Sidebar/SidebarSelection.swift`
- Modify: `macgit/Services/SidebarSettingsStore.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarPersonalChangesSection.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarPersonalChangeRow.swift`
- Create: `macgit/Views/MainWindow/Sidebar/SidebarPersonalChangeSectionActions.swift`
- Modify: `macgit/Views/MainWindow/SidebarView.swift`
- Modify: `macgit/Views/MainWindow/MainWindowView.swift`
- Test: `macgitTests/SidebarPersonalChangesTests.swift`

- [ ] Insert `PERSONAL CHANGES` after `WORKSPACE` and before `BRANCHES`.
- [ ] Add `SidebarSelection.personalChange(UUID)` and route it to the detail surface.
- [ ] Persist `personalChangesExpanded` with a backward-safe decode default.
- [ ] Render one row per profile with name, branch scope where space allows, and a text/icon state indicator that does not rely on color.
- [ ] Give Needs Attention and Staged Externally clear priority over ordinary Applied/Paused state.
- [ ] Keep profile loading and mutations outside Sidebar local state.
- [ ] Cover order, expansion persistence, row selection, empty/loading/error states, and accessibility labels.

### Task 3: Add the profile detail surface

**Files:**

- Create: `macgit/Views/PersonalChanges/PersonalChangeDetailView.swift`
- Create: `macgit/Views/PersonalChanges/PersonalChangeEntryRow.swift`
- Create: `macgit/Views/PersonalChanges/PersonalChangeStateView.swift`
- Create: `macgit/Views/PersonalChanges/PersonalChangeConfirmationSheet.swift`
- Modify: `macgit/Views/MainWindow/MainWindowView.swift`
- Test: `macgitTests/PersonalChangeActionPolicyTests.swift`

- [ ] Show profile metadata, current branch scope, protection setting, derived status, managed entries, and store issues.
- [ ] Add Apply and Pause actions with disabled reasons driven by pure action policy.
- [ ] Add Delete Profile and Revert and Delete as distinct actions with distinct confirmation copy.
- [ ] Delete Profile keeps the working tree unchanged.
- [ ] Revert and Delete appears only when a complete reverse is safe; execution remains service-owned.
- [ ] Explain that Git and other apps can still stage the content.
- [ ] Use item-driven sheets/alerts for selected profiles and provide VoiceOver labels for status icons.

### Task 4: Add shared File Status capture menus and sheet

**Files:**

- Create: `macgit/Views/PersonalChanges/PersonalChangeMenuContent.swift`
- Create: `macgit/Views/PersonalChanges/CreatePersonalChangeSheet.swift`
- Create: `macgit/Views/PersonalChanges/PersonalChangePatchPreview.swift`
- Create: `macgit/Views/PersonalChanges/PersonalChangeCaptureDraft.swift`
- Modify: `macgit/Views/FileStatus/FileStatusView.swift`
- Modify: `macgit/Views/FileStatus/FileStatusActionSelection.swift`
- Modify: `macgit/Views/Common/DiffView.swift`
- Test: `macgitTests/PersonalChangeMenuPolicyTests.swift`
- Test: `macgitTests/PersonalChangeCaptureDraftTests.swift`

- [ ] Use one `PersonalChangeMenuContent` in both File Status ellipsis and right-click menus.
- [ ] Offer Create New Profile and Add to eligible existing profile actions.
- [ ] Preserve current multi-selection semantics but reject a mixed selection containing any unsupported path with a precise reason.
- [ ] Opening from a file row preselects eligible hunks for that file and permits deselection before saving.
- [ ] Opening from a diff hunk or selected lines captures exactly that selection.
- [ ] Default `Protect from staging in Commit+` and `Keep changes applied` to on.
- [ ] Turning Keep Applied off makes the confirmation action explicitly read Save and Pause.
- [ ] Do not expose Stop Tracking, Ignore, or hidden Git-index flags as Personal Changes behavior.
- [ ] Ensure the existing Stage/Discard/Reset/Ignore menu ordering and disabled states remain unchanged outside the new submenu.

### Task 5: Annotate managed files and hunks without hiding Git state

**Files:**

- Create: `macgit/Views/PersonalChanges/PersonalChangeBadge.swift`
- Modify: `macgit/Views/FileStatus/FileStatusView.swift`
- Modify: `macgit/Views/Common/DiffView.swift`
- Test: `macgitTests/PersonalChangePresentationPolicyTests.swift`

- [ ] Keep every applied personal file in the ordinary Changed list.
- [ ] Add a compact Personal/profile badge to managed rows.
- [ ] Mark managed hunks/lines from controller-supplied classification.
- [ ] Distinguish personal-only, ordinary-only, and mixed hunks without claiming mixed content is protected yet.
- [ ] Preserve current file selection identity, pagination, diff reload, drag payload, and quick-action behavior.
- [ ] Show a temporary product warning that complete staging protection lands in Phase 3; do not mark the feature generally available before then.

### Task 6: Verify and close the phase

- [ ] Run Phase 1 tests plus new controller/policy/draft/sidebar tests.
- [ ] Run:

  ```bash
  rtk git diff --check
  rtk xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  ```

- [ ] Do not launch the app. Record Sidebar geometry, menu parity, focused-input behavior, and sheet lifecycle as manual acceptance items not verified by the build.
- [ ] Merge to `main` before marking Phase 2 `[completed]`.

## Acceptance Criteria

- Personal Changes appears as a dedicated section after Workspace.
- Selecting a profile shows its files, scope, protection preference, and derived current-worktree state.
- File row ellipsis and right-click menus expose identical Personal Changes actions.
- A user can capture exact file hunks/lines into a new or existing profile.
- Keep Applied leaves working files byte-identical; Save and Pause reverses only the captured patch.
- Managed content stays visible in Changed and is labeled in both file and diff surfaces.
- Apply, Pause, Delete Profile, and Revert and Delete use the Phase 1 transactional service.
- Existing File Status and Sidebar behavior remains unchanged for repositories with no profiles.

## Explicit Non-Goals

- No claim of complete staging protection until Phase 3.
- No automatic branch checkout behavior.
- No profile Update or overlap-repair UI beyond blocking invalid capture.
- No drag/drop into the Personal Changes section.
- No export/import or cloud sync.

