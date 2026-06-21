# Git Undo Roadmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide a phase-by-phase implementation map for Tower-style Git Undo in macgit so each action family can be started and verified independently.

**Architecture:** Phase 0+1A creates the shared runtime undo stack, executor, menu notification route, and file-level stage/unstage support. Every later phase extends the same `GitUndoOperation`, `GitUndoEntryFactory`, and `GitUndoExecutor` surface with one action family and focused integration tests.

**Tech Stack:** Swift 6, SwiftUI, XCTest, `xcodebuild`, existing `GitStatusService`, local Git repositories created in tests.

---

## Plan Index

- Phase 0 + 1A: [completed] [2026-06-19-git-undo-phase-0-1a.md](2026-06-19-git-undo-phase-0-1a.md) (branch: codex/git-undo-phase-0-1a)
- Phase 1B: [completed] [2026-06-19-git-undo-phase-1b-hunks-lines.md](2026-06-19-git-undo-phase-1b-hunks-lines.md) (branch: codex/git-undo-phase-1b)
- Phase 2: [completed] [2026-06-19-git-undo-phase-2-commits.md](2026-06-19-git-undo-phase-2-commits.md) (branch: codex/git-undo-phase-2)
- Phase 3A: [completed] [2026-06-19-git-undo-phase-3a-stash-save-drop.md](2026-06-19-git-undo-phase-3a-stash-save-drop.md) (branch: codex/git-undo-phase-3a)
- Phase 3B: [completed] [2026-06-19-git-undo-phase-3b-stash-apply-pop.md](2026-06-19-git-undo-phase-3b-stash-apply-pop.md) (branch: codex/git-undo-phase-3b)
- Phase 4: [completed] [2026-06-19-git-undo-phase-4-local-branches.md](2026-06-19-git-undo-phase-4-local-branches.md) (branch: codex/git-undo-phase-4)
- Phase 5: [completed] [2026-06-19-git-undo-phase-5-discard-remove.md](2026-06-19-git-undo-phase-5-discard-remove.md) (landed on `main` at `0115a7f`)
- Phase 6: [in progress] [2026-06-19-git-undo-phase-6-history-actions.md](2026-06-19-git-undo-phase-6-history-actions.md) (branch: codex/git-undo-phase-6, worktree: .worktrees/codex-git-undo-phase-6)
- Phase 7: [pending] [2026-06-19-git-undo-phase-7-remote-actions.md](2026-06-19-git-undo-phase-7-remote-actions.md)

## Recommended Order

1. Finish Phase 0 + 1A first. It creates `GitUndoManager`, `GitUndoExecutor`, Cmd+Z / Shift+Cmd+Z menu routing, and stage/unstage file undo.
2. Do Phase 1B next because it reuses the same index patch semantics as Phase 1A.
3. Do Phase 2 after Phase 1B. Commit undo is simple when scoped to normal commits and guarded by `HEAD` checks.
4. Do Phase 3A before 3B. Save/drop stash undo is safer than apply/pop.
5. Do Phase 4 after Phase 2. Branch undo depends on reliable ref capture and expected-HEAD checks.
6. Do Phase 5 only after the team accepts local backup snapshots under `.git/macgit/undo`.
7. Do Phase 6 after reset/commit primitives are stable.
8. Do Phase 7 last because remote undo needs explicit user confirmation and `--force-with-lease` safety.

## Shared Rules for Every Phase

- Every undo entry is registered only after the original Git action succeeds.
- Every undo or redo refreshes `SyncState` and posts `.repositoryDidChange`.
- Every destructive inverse checks an expected state before running.
- If a precondition fails, restore the popped entry to its original stack and show an error.
- Do not persist undo stacks across app launches in these phases.

## Self-Review

Spec coverage:

- All previously discussed phases are represented by separate plan files.
- The dependency order allows implementing one action family at a time.

Placeholder scan:

- This roadmap links concrete plan filenames and contains no open implementation slots.

Type consistency:

- All phases extend the same Phase 0+1A types: `GitUndoOperation`, `GitUndoEntryFactory`, `GitUndoExecutor`, and `GitUndoManager`.
