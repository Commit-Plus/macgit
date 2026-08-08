# Git Flow Lite Roadmap

## Goal

Deliver a safe, repository-local Git Flow experience for Feature, Bugfix, Release, and Hotfix branches. Keep the initial product deliberately small while preserving seams for future Branch Workflows.

## Phases

- [completed] [Phase 1: Configuration and Start flows](2026-08-08-git-flow-lite-phase-1-configuration-and-start.md), merged to `main` from `codex/git-flow-lite-phase-1`
- [completed] [Phase 2: Finish Feature and Bugfix plus sidebar workflow surface](2026-08-08-git-flow-lite-phase-2-feature-bugfix-finish.md), implemented on `codex/git-flow-lite-phase-2`
- [completed] [Phase 3: Finish Release and Hotfix with multi-target merge, annotated tag, conflict checkpoint, Resume, and Abort](2026-08-08-git-flow-lite-phase-3-release-hotfix-finish.md), implemented on `codex/git-flow-lite-phase-3`
- [pending] [Phase 4: Worktree-aware Start flows with repository-local default, safe cleanup, and guarded Undo/Redo](2026-08-08-git-flow-lite-phase-4-worktree-aware-start.md)
- [pending] [Phase 5: Finish preferences for Feature/Bugfix Merge or Rebase and Release/Hotfix annotated tags](2026-08-08-git-flow-lite-phase-5-finish-preferences.md)
- [pending] [Phase 6: UX polish, branch-role badges, accessibility, feature-access enforcement, and recovery hardening](2026-08-08-git-flow-lite-phase-6-polish-and-hardening.md)

## Shared constraints

- Use native Git commands through `GitStatusService`; do not require a `git-flow` executable.
- Keep configuration repository-local and out of Firebase and tracked working-tree files.
- Feature and Bugfix share an execution policy but remain separate user-facing types.
- Through Phase 4, Finish uses `--no-ff` only. Phase 5 may add Rebase and fast-forward for Feature/Bugfix; Release/Hotfix keep the two-target merge policy. Squash and custom workflow graphs remain out of scope.
- Do not automatically push or delete remote refs.
- Views remain rendering and callback surfaces; orchestration belongs in `MainWindowView`, planning in a pure planner, and Git execution in services.
- Register Undo only after the original operation succeeds and refresh `SyncState` plus `.repositoryDidChange` after mutations.
- Keep Git Flow configuration and recovery repository-local in the Git common directory. Repository paths, branch names, and checkpoints never sync to Firebase.
- Route Git Flow access through the existing feature-policy resolver: Free public/local-only, active Pro private, and unresolved visibility fails closed. Resume/Abort remain available as recovery actions.
- Do not launch the app. Focused tests and a successful macOS build are the verification boundary.

## Completion

The roadmap is complete when all four topic types can start in the current working copy or a linked worktree; Feature/Bugfix can finish by Merge or Rebase; Release/Hotfix support configurable annotated tags and resume correctly after conflicts; branch roles, recovery, accessibility, and access-policy states are clear; local Undo observes expected-ref/worktree guards; all phase branches are merged to `main`; and focused tests plus the final macOS build pass.
