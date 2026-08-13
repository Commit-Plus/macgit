# Personal Changes Phase 4: Lifecycle, Branch/Worktree Semantics, and Recovery

**Branch:** `codex/personal-changes-phase-4-lifecycle-recovery`

**Goal:** Harden Personal Changes for long-lived daily use by completing Update/remove/delete semantics, handling branch and linked-worktree changes explicitly, and providing recovery for drift, partial application, and obsolete patches.

**Architecture:** A pure lifecycle planner produces preflight steps and recovery requirements. `MainWindowView` coordinates app-managed checkout with existing repository-operation UI; Personal Change services remain responsible for patch mutations and `GitStatusService` remains responsible for Git checkout. External repository changes trigger inspection and user guidance, never silent patch mutation.

## Prerequisites

- Phase 3 is merged and every staging/commit entry point is protected.
- Start the branch from clean, updated `main`.
- Re-read current checkout, branch-creation, worktree-open, refresh, Undo/Redo, and repository-operation paths before integrating lifecycle behavior.
- Preserve existing checkout safety, worktree occupancy checks, and current-branch refresh generation guards.

## Tasks

### Task 1: Implement Update and membership editing

**Files:**

- Create: `macgit/Services/PersonalChangeUpdatePlanner.swift`
- Modify: `macgit/Services/PersonalChangeService.swift`
- Modify: `macgit/App/PersonalChangesController.swift`
- Modify: `macgit/Views/PersonalChanges/PersonalChangeDetailView.swift`
- Modify: `macgit/Views/PersonalChanges/CreatePersonalChangeSheet.swift`
- Test: `macgitTests/PersonalChangeUpdateIntegrationTests.swift`

- [ ] Update only explicitly selected stored entries/hunks after confirming the previous personal content is represented in the worktree.
- [ ] Never absorb unrelated ordinary changes from the same file automatically.
- [ ] Detect and block overlapping ownership between protected profiles; offer Move to Profile only as an explicit atomic operation.
- [ ] Remove Entry and Remove from Profile change definitions only and keep working files/index unchanged.
- [ ] Delete the profile automatically only after its final entry is removed and the user confirms the empty-profile action.
- [ ] Preserve UUID identity and creation date across Update; update fingerprints and modification date atomically.

### Task 2: Complete delete and destructive-revert recovery

**Files:**

- Create: `macgit/Services/PersonalChangeRemovalPlanner.swift`
- Modify: `macgit/Services/PersonalChangeService.swift`
- Modify: `macgit/Views/PersonalChanges/PersonalChangeConfirmationSheet.swift`
- Test: `macgitTests/PersonalChangeRemovalIntegrationTests.swift`

- [ ] Keep Delete Profile non-destructive to working files.
- [ ] Revert and Delete preflights every entry, reverses all entries once, then deletes the persisted profile.
- [ ] If persistence deletion fails after reverse, retain/recreate the profile and surface a recovery issue rather than losing ownership metadata.
- [ ] Disable Revert and Delete for Partially Applied, Needs Attention, Staged Externally, or unavailable-branch state.
- [ ] Add guarded Undo only if the exact expected worktree/index state can be verified; otherwise leave Undo out and document why.

### Task 3: Add branch-aware checkout preflight and optional coordinated transition

**Files:**

- Create: `macgit/Services/PersonalChangeCheckoutPlanner.swift`
- Modify: `macgit/Views/MainWindow/MainWindowView.swift`
- Modify relevant checkout coordinator files discovered at kickoff.
- Create: `macgit/Views/PersonalChanges/PersonalChangeCheckoutSheet.swift`
- Test: `macgitTests/PersonalChangeCheckoutPlannerTests.swift`
- Test: `macgitTests/PersonalChangeCheckoutIntegrationTests.swift`

- [ ] Before Commit+-managed checkout, inspect applied branch-scoped profiles and matching profiles for the destination branch.
- [ ] Default behavior remains explicit: show what must be paused and what can be applied; do not rewrite files merely because the user selected a branch.
- [ ] Offer coordinated Pause Current → Checkout → Apply Matching only when all steps preflight safely.
- [ ] If checkout fails after Pause, reapply the old profile only when its expected state still matches; otherwise expose a recovery checkpoint.
- [ ] If destination Apply fails after successful checkout, remain on the checked-out branch, keep the destination profile stored/paused, and report the exact affected entries.
- [ ] Preserve normal checkout behavior when no relevant profiles exist.
- [ ] Detached HEAD and branch deletion make branch-scoped profiles unavailable without deleting them.

### Task 4: Handle linked worktrees and external branch changes

**Files:**

- Modify: `macgit/App/PersonalChangesController.swift`
- Modify: `macgit/Services/PersonalChangeInspector.swift`
- Modify: `macgit/Views/PersonalChanges/PersonalChangeDetailView.swift`
- Modify: `macgit/Views/MainWindow/Sidebar/SidebarPersonalChangeRow.swift`
- Test: `macgitTests/PersonalChangeWorktreeIntegrationTests.swift`

- [ ] Share definitions through the Git common directory while inspecting status independently per worktree path.
- [ ] Do not let an Applied badge in worktree A imply Applied in worktree B.
- [ ] On app activation/background current-branch detection, report out-of-scope applied content and available destination profiles without automatic mutation.
- [ ] Ensure opening a linked worktree creates/uses a controller keyed to that working-copy URL.
- [ ] Cover one profile Applied in one worktree and Paused/Needs Attention in another.
- [ ] Preserve manual Sidebar expansion and existing targeted branch-only refresh behavior.

### Task 5: Add drift and obsolete-patch recovery

**Files:**

- Create: `macgit/Views/PersonalChanges/PersonalChangeRecoveryView.swift`
- Create: `macgit/Services/PersonalChangeRecoveryPlanner.swift`
- Modify: `macgit/Services/PersonalChangeInspector.swift`
- Test: `macgitTests/PersonalChangeRecoveryTests.swift`

- [ ] Explain which path failed and whether the patch is partial, conflicting, staged, out of scope, or already integrated into the branch.
- [ ] Offer safe actions only: Preview, Retry inspection, recapture selected current content, remove ownership while keeping files, or open the file/diff.
- [ ] Never use hard reset, checkout-file overwrite, or best-effort reverse as recovery.
- [ ] Detect when the profile's personal result is already present in the current committed base and mark it Obsolete/Integrated rather than Applied.
- [ ] Require explicit confirmation before removing an obsolete profile.
- [ ] Redact patch/file content from diagnostic exports and error logs.

### Task 6: Verify reliability and close the phase

- [ ] Run all Personal Changes tests plus focused branch checkout, worktree, stage, commit, and Undo suites sequentially.
- [ ] Run `rtk git diff --check` and the macOS build.
- [ ] Do not launch the app. Record checkout-sheet lifecycle, multi-window worktree status, state badges, and recovery navigation as manual runtime acceptance.
- [ ] Update roadmap and result notes only after merge to `main`.

## Acceptance Criteria

- Update changes only selected personal ownership and never absorbs unrelated edits.
- Remove/Delete keep working files unchanged; Revert and Delete is separately confirmed and transactional.
- Commit+-managed checkout explains branch-scoped transitions and can perform a fully preflighted coordinated transition.
- External checkout never silently applies or pauses a profile.
- Linked worktrees share definitions but show independent status.
- Partial, conflicting, staged, out-of-scope, and already-integrated states have non-destructive recovery paths.
- Existing checkout/worktree behavior remains unchanged when no relevant profile exists.

## Explicit Non-Goals

- No default automatic Apply/Pause on external checkout.
- No automatic patch conflict resolution.
- No profile sharing between users.
- No export/import until Phase 5.
- No Firebase or cloud sync.

