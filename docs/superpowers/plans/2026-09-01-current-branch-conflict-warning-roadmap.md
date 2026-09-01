# Current Branch Conflict Warning Roadmap

Warn when the checked-out topic branch has not integrated recent upstream or base-branch commits, predict textual merge conflicts without touching the worktree, and provide one safe update action.

## Architecture

- Limit monitoring and presentation to the checked-out branch.
- Keep Git inspection and mutation in `GitStatusService`; keep `SyncState` responsible for operation lifecycle, Git Undo registration, and repository refresh notifications.
- Preserve the existing upstream ahead/behind badges. Add a distinct integration warning for commits missing from the configured base branch.
- Resolve the base from enabled Git Flow configuration first, then fall back to the tracked remote's default branch.
- Compare and merge remote-tracking refs directly so the local base branch does not need to be checked out or updated.
- Never automatically commit or push after the update.

## Phases

- [completed] **Phase 1 — Current-branch warning and one-click update**
  - Plan: [2026-09-01-current-branch-conflict-warning-phase-1.md](2026-09-01-current-branch-conflict-warning-phase-1.md)
  - Detect upstream drift and base-branch drift for the current branch.
  - Preflight the base merge with `git merge-tree --write-tree` and distinguish ordinary drift from predicted textual conflicts.
  - Add an accessible sidebar warning with details and a single update action.
  - Fetch, update from upstream when needed, merge the base remote-tracking ref, and register Git Undo after success.
  - Add focused base-resolution, conflict-prediction, and update integration tests.
  - Annotate changed/staged File Status rows whose paths are predicted to conflict with the resolved base branch.

## Shared safety rules

- Disable the update while the worktree is dirty, Git has an operation in progress, or another repository operation is active.
- Recompute all refs after fetch before mutating the current branch.
- Do not auto-stash, auto-commit, force-push, or push.
- If Git reports conflicts, retain the merge state and route the user to the existing conflict-resolution flow.
- Do not present `merge-tree` as detecting semantic conflicts.
