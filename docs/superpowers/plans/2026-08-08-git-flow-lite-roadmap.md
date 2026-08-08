# Git Flow Lite Roadmap

## Goal

Deliver a safe, repository-local Git Flow experience for Feature, Bugfix, Release, and Hotfix branches. Keep the initial product deliberately small while preserving seams for future Branch Workflows.

## Phases

- [completed] [Phase 1: Configuration and Start flows](2026-08-08-git-flow-lite-phase-1-configuration-and-start.md), merged to `main` from `codex/git-flow-lite-phase-1`
- [completed] [Phase 2: Finish Feature and Bugfix plus sidebar workflow surface](2026-08-08-git-flow-lite-phase-2-feature-bugfix-finish.md), implemented on `codex/git-flow-lite-phase-2`
- [pending] Phase 3: Finish Release and Hotfix with multi-target merge, annotated tag, conflict checkpoint, Resume, and Abort
- [pending] Phase 4: Worktree-aware Start flows
- [pending] Phase 5: Advanced finish preferences for merge/rebase policy
- [pending] Phase 6: UX polish, branch-role badges, accessibility, and complete edge-case coverage

## Shared constraints

- Use native Git commands through `GitStatusService`; do not require a `git-flow` executable.
- Keep configuration repository-local and out of Firebase and tracked working-tree files.
- Feature and Bugfix share an execution policy but remain separate user-facing types.
- Version 1 uses `--no-ff` merge behavior only; no rebase, squash, or custom workflow graph.
- Do not automatically push or delete remote refs.
- Views remain rendering and callback surfaces; orchestration belongs in `MainWindowView`, planning in a pure planner, and Git execution in services.
- Register Undo only after the original operation succeeds and refresh `SyncState` plus `.repositoryDidChange` after mutations.
- Do not launch the app. Focused tests and a successful macOS build are the verification boundary.

## Completion

The roadmap is complete when all four topic types can be started and finished safely, Release and Hotfix resume correctly after conflicts, local Undo observes expected-ref guards, all phase branches are merged to `main`, and focused tests plus the final macOS build pass.
