# Git Flow Lite Phase 4: Worktree-Aware Start Flows

Status: completed on `codex/git-flow-lite-phase-4`.

**Implementation branch:** `codex/git-flow-lite-phase-4`

## Goal

Let users start Feature, Bugfix, Release, and Hotfix work either in the current working copy or in a new linked worktree, without changing the Finish behavior delivered in Phases 2 and 3.

This phase remains intentionally small: Commit+ creates one new topic branch, optionally attaches it to one new worktree, and never pushes anything.

## Prerequisites and session kickoff

- Phase 3 must already be present on `main`.
- Start from a clean `main`; do not create a separate Codex worktree for this phase.
- Create the implementation branch with `git switch -c codex/git-flow-lite-phase-4`.
- Read the roadmap and the Phase 1-3 plans before editing code.
- Preserve all existing current-working-copy Start behavior as the compatibility baseline.

## Product decisions

- Add two Start destinations: `Current Working Copy` and `New Worktree`.
- Keep `Current Working Copy` as the migration-safe default for existing configurations.
- Store one repository-local default Start destination in `GitFlowConfiguration`; the Start sheet may override it for a single operation.
- New-worktree Start does not switch the current repository window away from its current branch.
- The default worktree path and label behavior must reuse the existing Worktrees feature instead of introducing a second naming system.
- Offer `Open after create`, defaulting to on. Opening uses the existing `openWorktreeInNewWindow(at:)` path.
- A dirty current working copy blocks current-working-copy Start, but does not block new-worktree Start because no checkout or file mutation occurs there.
- An unfinished merge, rebase, cherry-pick, or revert still blocks both Start destinations.
- Do not add automatic worktree removal to Finish. A topic branch checked out in a linked worktree remains protected by the existing Finish validation until the user closes/removes or changes that worktree.

## Data model and persistence

- Add a Codable, Equatable Start destination enum, for example `GitFlowStartDestination` with `.currentWorkingCopy` and `.newWorktree`.
- Extend `GitFlowConfiguration` with `defaultStartDestination`.
- Decode missing `defaultStartDestination` as `.currentWorkingCopy` so Phase 1-3 configuration files remain valid.
- Extend `GitFlowStartPlan` with execution data instead of placing UI-only state in the service:
  - destination;
  - optional normalized worktree path;
  - optional trimmed worktree label.
- Keep `openAfterCreate` in `MainWindowView`/sheet state. It controls presentation after success and is not a Git execution concern.
- Extend `GitFlowStartResult` so callers can distinguish a current-working-copy checkout from a created worktree and can register the correct Undo entry.

## UI work

### Repository Settings

- Add a compact `Start behavior` row to the Git Flow tab in `RepositorySettingsSheetView`.
- Use a menu or segmented picker labeled `Start new flows in` with `Current Working Copy` and `New Worktree`.
- Keep branch and prefix controls unchanged.
- Explain that the selection is only a default and can be changed from the Start sheet.

### Start sheet

- Extend `StartGitFlowSheet` with a destination picker initialized from `configuration.defaultStartDestination`.
- For `Current Working Copy`, retain the existing branch name, starting point, and checkout preview.
- For `New Worktree`, show:
  - resolved full branch name;
  - base branch;
  - suggested path using the existing worktree path convention;
  - optional label;
  - `Open after create` checkbox.
- Recompute the suggested path while the topic name changes until the user manually edits the path. After a manual edit, do not overwrite it.
- Preview the exact result: branch only and checkout, or branch plus linked worktree at the selected path.
- Keep validation inline and disable the default action while the branch name or path is invalid.

## Service behavior

Split `GitFlowService.start` by destination while sharing branch-name, base-branch, unfinished-operation, and ref validation.

### Current working copy

- Preserve the Phase 1 sequence:
  1. require no unfinished operation;
  2. require a clean current working tree;
  3. validate base and new branch;
  4. create and check out the topic branch;
  5. return the previous ref and created tip.

### New worktree

- Use `GitStatusService.addWorktree(at:target:label:in:)` with `.newBranch(name:base:)`.
- Require an absolute, normalized path.
- Reject the repository root, the main worktree path, a path already registered as a worktree, and any path that already exists. Keep this conservative even if Git could accept an empty directory.
- Validate that the new branch is absent and valid immediately before `git worktree add -b`.
- Allow uncommitted changes in the current worktree, but never run checkout/reset there.
- If Git creates the branch but worktree creation fails, inspect the actual refs/worktree list and clean up only the newly created branch when it still points at the expected base tip and is not attached to a worktree. Never force-delete an ambiguous ref.
- On success, refresh branch and worktree state and post `.repositoryDidChange` once.

## Undo and Redo

- Current-working-copy Start keeps the Phase 1 Undo/Redo behavior.
- Add guarded Git Undo operations for a worktree-created Start rather than issuing raw Git commands from the view.
- Undo must:
  1. confirm the exact worktree path is still attached to the expected branch;
  2. require that worktree to be clean and the branch tip to equal the recorded created tip;
  3. remove the worktree without `--force`;
  4. delete the local branch with the expected-tip guard.
- Redo must recreate the branch and worktree at the same explicit path from the recorded base tip and restore its label.
- Give Undo a confirmation explaining that the linked worktree folder and its local branch will be removed.
- If the worktree is open, dirty, moved, locked, missing, on another branch, or has new commits, Undo must fail without partially deleting it.
- Register Undo only after the complete Start operation succeeds.

## Expected file map

- Modify `macgit/Models/GitFlowConfiguration.swift`.
- Modify `macgit/Models/GitFlowStartPlan.swift`; add a separate Start-destination model file only if it improves clarity.
- Modify `macgit/Services/GitFlowPlanner.swift` and `macgit/Services/GitFlowService.swift`.
- Reuse and, where required, extend `macgit/Services/GitStatusService+Worktree.swift`.
- Extend `macgit/Services/GitUndoModels.swift` and `macgit/Services/GitUndoExecutor.swift` with guarded worktree operations.
- Modify `macgit/Views/Workflow/StartGitFlowSheet.swift`.
- Modify `macgit/Views/Common/RepositorySettingsSheetView.swift`.
- Modify `macgit/Views/MainWindow/MainWindowView+GitFlow.swift`, `MainWindowView+Sheets.swift`, and state in `MainWindowView.swift` only as needed for orchestration/open-after-create.
- Add `macgitTests/GitFlowLitePhase4Tests.swift` and focused Git Undo tests.
- Every new Swift file must include the AGPL header required by `AGENTS.md`.

## Test plan

- Configuration decoding defaults old files to current-working-copy Start.
- Configuration round-trips both destination values through `GitFlowConfigurationStore` and linked worktrees see the same value.
- Planner emits correct base branch, prefix, and destination for all four topic kinds.
- Current-working-copy Start remains blocked by dirty state and still checks out the new branch.
- New-worktree Start succeeds while the current worktree is dirty and leaves its branch/HEAD/files unchanged.
- New-worktree Start creates the expected branch, path, label, and worktree registration.
- Existing branch, invalid branch, missing base, existing path, registered path, repository-root path, and unfinished-operation cases fail before mutation.
- A simulated partial failure cleans up only an untouched newly created ref.
- Undo/Redo succeeds for an unchanged clean worktree and refuses dirty, moved, locked, retargeted, missing, or advanced worktrees.
- `GitFlowCommandState` continues disabling Start during a pending Finish or active repository operation.

## Acceptance criteria

- Every Start flow can run in either the current working copy or a new linked worktree.
- Existing repositories behave exactly as before until the user changes the default or selects New Worktree in the sheet.
- Starting in a worktree never checks out another branch or modifies files in the current working copy.
- Suggested paths are consistent with the existing Create Worktree experience and remain user-editable.
- Successful creation refreshes both Branches and Worktrees, optionally opens the new worktree, and registers guarded Undo/Redo.
- Failure cannot leave an ambiguous branch/worktree pair silently behind.
- No remote ref is created, pushed, or deleted.

## Explicit non-goals

- No automatic worktree cleanup during Finish.
- No per-topic default worktree root.
- No worktree templates, sparse checkout, locking, or background pruning.
- No merge/rebase or tag preference changes; those belong to Phase 5.
- No branch-role badge or broad visual polish; those belong to Phase 6.

## Verification

- Run the Phase 1-4 Git Flow tests plus focused Worktree/Git Undo tests.
- Run `git diff --check`.
- Run `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`.
- Do not launch the app. If the full test host aborts during Firebase bootstrap, do not loop it; retain targeted-test and successful-build evidence.

## Result

- Repository settings persist a backward-compatible default Start destination, while each Start sheet can override it.
- All four topic kinds can create their branch in the current working copy or at the shared Worktrees `.worktrees/<branch>` path convention with an optional label and Open-after-create behavior.
- New-worktree Start permits a dirty current working copy, validates the path and refs before mutation, and conservatively cleans up a partially created branch/worktree pair.
- Git Undo removes only the exact clean, unlocked, unopened worktree at the recorded branch tip; Redo restores the same path, branch, base tip, and label.
- Phase 1-4 focused tests compiled, but the test host hit the documented Firebase bootstrap `Early unexpected exit` / `abort()` and was not rerun. `git diff --check` and the macOS build passed without launching the app.
