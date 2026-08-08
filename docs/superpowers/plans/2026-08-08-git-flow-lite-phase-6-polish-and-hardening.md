# Git Flow Lite Phase 6: UX Polish and Hardening

Status: pending.

**Implementation branch:** `codex/git-flow-lite-phase-6`

## Goal

Make Git Flow Lite feel complete in daily use: surface branch roles and paused operations clearly, close accessibility and feature-access gaps, and harden the edge cases around configuration, linked worktrees, recovery, and execution races.

This is a stabilization phase. It must not grow Git Flow Lite into a custom workflow designer.

## Prerequisites and session kickoff

- Phases 4 and 5 must be merged to `main` before this phase begins.
- Start from a clean `main`; do not create a separate Codex worktree for this phase.
- Create the implementation branch with `git switch -c codex/git-flow-lite-phase-6`.
- Read the roadmap and all preceding Git Flow phase plans before editing code.
- Inventory current screenshots/runtime behavior before changing layout; preserve existing sidebar density and native macOS menu behavior.

## Product decisions

- Branch-role presentation is informational. It never renames, moves, or mutates a branch.
- Main and Develop receive explicit roles; topic branches receive Feature, Bugfix, Release, or Hotfix roles from the enabled repository configuration.
- Role badges use text plus restrained styling, not color alone.
- A pending Finish checkpoint is shown inline in the Git Flow sidebar section with Resume and Abort actions, while existing app-menu/context-menu recovery remains available.
- Recovery actions remain available even if entitlement or remote policy changes after an operation started; users must never be stranded in a merge/rebase conflict.
- Git Flow setup, configuration, Start, and new Finish operations use the existing Firebase-backed `.gitFlow` feature-access decision. No new plan checks or quota logic may be invented.
- Free remains allowed for public and local-only repositories; hosted private repositories require active Pro; unknown visibility and unresolved policy fail closed.
- Disable Workflow remains available without authorization because it is a local safety/configuration action.

## Branch-role resolution and badges

- Add a pure role resolver, for example `GitFlowBranchRoleResolver`, instead of embedding prefix logic in branch-row rendering.
- Resolve roles only when Git Flow is enabled:
  - exact configured Main branch -> Main;
  - exact configured Develop branch -> Develop;
  - configured prefix plus non-empty suffix -> matching topic kind;
  - otherwise no role.
- Main/Develop exact matches take precedence over topic prefixes.
- If custom prefixes overlap, choose the longest valid prefix deterministically. Also update configuration validation/help text so ambiguous prefix setups cannot silently change role depending on enum order.
- Add a compact badge to local branch rows without displacing the current HEAD indicator, sync badge, drag/drop state, folder hierarchy, or context-menu hit target.
- Suggested labels: `MAIN`, `DEVELOP`, `FEATURE`, `BUGFIX`, `RELEASE`, `HOTFIX`; use existing typography conventions rather than a new badge design system.
- Do not add role badges to remote branches in this phase.

## Git Flow sidebar polish

- Keep the existing Show/Hide setting and expanded/collapsed persistence.
- When no Finish is pending, retain the four Start rows and Tower-style header context menu.
- When a checkpoint is pending, add an inline recovery row/card showing:
  - flow kind and source branch;
  - current recovery step (primary merge, secondary merge, or topic rebase);
  - `Resume` and destructive `Abort` controls;
  - guidance to resolve conflicts in File Status before Resume when Git reports conflicts.
- Disable new Start/Finish actions while recovery is pending but keep Edit Workflow visible.
- Ensure the app menu, toolbar Git Flow menu, sidebar header context menu, and inline recovery row all derive enablement from the same `GitFlowCommandState`/policy rather than duplicating conditions.
- Improve Finish sheet summaries so Release/Hotfix clearly show both targets and tag result, while Feature/Bugfix clearly show Merge versus Rebase.

## Feature-access boundary

- Add one reusable `authorizeGitFlowAccess(forceRefresh:presentNotice:)` coordinator beside the existing Pull Request authorization pattern.
- Resolve through `RepositoryVisibilityController.accessDecision(for:.gitFlow, ...)` with current accounts, entitlement, and feature policy.
- Authorize before presenting Git Flow setup/configuration UI and before building/executing any new Start or Finish plan.
- Cover every entry path:
  - app/toolbar Git Flow menu;
  - sidebar Start buttons;
  - sidebar header context menu;
  - settings deep link;
  - keyboard/notification command path;
  - direct coordinator callbacks used by sheets.
- Re-authorize at the execution boundary so a previously opened sheet cannot bypass a changed policy.
- Present the existing Sign In, Pro upgrade, disabled-feature, or visibility-unavailable UI. Do not add a second Git Flow-specific paywall implementation.
- Retry visibility for `.gitFlow` from the existing access notice path.
- Resume Finish, Abort Finish, and Disable Workflow bypass new-action authorization but still respect active-operation serialization.
- Add focused tests proving denial occurs before any Git mutation or settings presentation.

## Accessibility and native macOS behavior

- Add explicit accessibility labels/hints/values to:
  - Git Flow section header and expanded state;
  - Start/Finish/Resume/Abort controls;
  - branch-role badges;
  - destination and strategy pickers;
  - tag toggle/name field;
  - validation and recovery messages.
- Ensure icon-only controls have meaningful labels and tooltips.
- Preserve full keyboard operation: initial focus in the topic/tag field, default/cancel shortcuts, Space for toggles, and menu keyboard equivalents where already defined.
- Verify VoiceOver reading order follows title, inputs, preview/warning, then actions.
- Do not rely on hover, color, or disabled opacity as the only explanation for unavailable actions.
- Keep sheets usable at the existing minimum width and with longer localized text; avoid fixed heights that clip validation/recovery copy.

## Recovery and execution hardening

- Treat the checkpoint's embedded plan as authoritative even if configuration changes while Finish is paused.
- Add an explicit recovery-store load result (`none`, valid checkpoint, corrupt/unsupported checkpoint) instead of silently treating malformed data as no checkpoint.
- A corrupt checkpoint or Git operation without a usable checkpoint must block new Git Flow mutations and direct the user to File Status/manual Git recovery. Do not delete recovery data automatically.
- Re-check target existence, target worktree ownership, tag collision, current source ref, and expected tips immediately before each mutation, not only when the sheet opens.
- Keep the checkpoint after any partially completed multi-step failure until Resume or Abort completes.
- Abort must use expected-ref guards before resetting completed targets. If refs drift, stop and explain what changed rather than applying a hard reset.
- Resume/Abort refresh Branches, Tags, Worktrees, `SyncState`, current branch, command state, and `.repositoryDidChange` consistently.
- Ensure linked worktrees read the same configuration/checkpoint from the Git common directory and do not present contradictory recovery actions.
- Ensure a Release/Hotfix tag collision race or source-deletion warning cannot be reported as a fully clean success.
- Keep remote refs untouched in every recovery path.

## Configuration hardening

- Preserve backward decoding for every configuration version introduced in Phases 1, 4, and 5.
- Distinguish missing configuration from corrupt configuration. Missing means Git Flow is not yet configured; corrupt means show a recoverable error and do not overwrite the file until the user explicitly saves valid settings.
- Validate Main/Develop existence, difference, branch-name validity, non-empty/unique/unambiguous prefixes, Start destination defaults, and Finish preferences in one planner-owned validation boundary.
- Continue storing only under the Git common directory; never add a tracked file or Firebase sync for repository Git Flow state.

## Expected file map

- Add a pure branch-role model/resolver under `macgit/Models` or `macgit/Services` and focused tests.
- Modify local branch row/presentation files under `macgit/Views/MainWindow/Sidebar/` without changing remote-branch rendering.
- Modify `SidebarGitFlowSection.swift`, `SidebarGitFlowActions.swift`, and shared command-state/menu content.
- Modify `StartGitFlowSheet.swift`, `FinishGitFlowSheet.swift`, and the Git Flow portion of `RepositorySettingsSheetView.swift` for accessibility and summaries.
- Modify `MainWindowView+GitFlow.swift`, `MainWindowView.swift`, and feature-access notice/retry wiring.
- Harden `GitFlowConfigurationStore.swift`, `GitFlowRecoveryStore.swift`, `GitFlowPlanner.swift`, and `GitFlowService.swift`.
- Extend existing Phase 1-5 tests and add `macgitTests/GitFlowLitePhase6Tests.swift` for role, policy, recovery, and race behavior.
- Every new Swift file must include the AGPL header required by `AGENTS.md`.

## Test plan

### Role/UI state

- Main, Develop, all four topic kinds, ordinary branches, disabled configuration, custom prefixes, overlapping prefixes, and empty suffixes resolve deterministically.
- Branch badges do not replace HEAD or sync status and do not appear on remote branches.
- Sidebar and app-menu Start/Finish/Resume/Abort enablement stays consistent for disabled workflow, active operation, detached HEAD, recognized topic, and pending checkpoint states.
- Recovery step text matches primary merge, secondary merge, and topic rebase checkpoints.

### Access

- Public and local-only Free decisions allow configuration, Start, and Finish.
- Private Free requires Pro; active Pro allows it.
- Unknown visibility, malformed/disabled policy, and unresolved access fail before UI presentation or Git mutation.
- Every menu/sidebar/notification/sheet callback path reaches the same authorization helper.
- Resume, Abort, and Disable remain available after entitlement/policy denial.

### Recovery/configuration

- Configuration changes during a checkpoint do not alter Resume targets, strategy, or tag.
- Missing, old-version, valid, corrupt, and unsupported configuration/checkpoint payloads produce distinct safe outcomes.
- Target branch deletion/rename, target checked out in another worktree, source ref drift, tag collision race, and target-tip drift stop at the correct checkpoint.
- Abort refuses unexpected refs instead of hard-resetting them.
- Linked worktrees observe one shared pending checkpoint and configuration.
- Refresh/notification behavior runs after success, recoverable failure, Resume, and Abort.

### Regression

- Phase 1-5 happy paths, Undo/Redo, dirty-worktree checks, branch deletion warnings, and no-remote-mutation assertions continue passing.
- Existing non-Git-Flow branch/sidebar/worktree behavior remains unchanged.

## Acceptance criteria

- Users can identify Main, Develop, and topic branch roles at a glance without losing existing branch status information.
- A paused Finish is obvious and recoverable from the sidebar and existing menus.
- Git Flow is authorized consistently with the shipped Firebase feature policy and cannot be bypassed by alternate UI paths.
- Accessibility labels, reading order, focus, shortcuts, and non-color cues cover all Git Flow controls.
- Malformed local state and ref/worktree races fail closed without silent resets, lost work, or remote mutations.
- All earlier Git Flow behavior remains compatible and the repository-local storage boundary is preserved.

## Explicit non-goals

- No arbitrary Branch Workflow graph, custom parent relationships, or extra topic types.
- No remote push, remote branch deletion, tag push, pull request automation, CI/release integration, or changelog generation.
- No automatic conflict resolution.
- No remote-branch role badges or graph-lane decoration.
- No Firebase persistence of branch names, paths, Git Flow configuration, or checkpoints.

## Verification

- Run all focused Git Flow Phase 1-6 tests plus affected feature-access, sidebar, worktree, and Git Undo tests.
- Run `git diff --check`.
- Run `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`.
- Do not launch the app. If the full test host aborts during Firebase bootstrap, do not loop it; retain targeted-test and successful-build evidence.
- Record any runtime-only visual QA still needed from the user instead of claiming it from a successful build.
