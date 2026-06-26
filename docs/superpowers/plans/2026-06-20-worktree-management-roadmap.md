# Worktree Management Roadmap

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide a phase-by-phase implementation map for Git worktree management in macgit so each phase produces working, testable software on its own.

**Architecture:** Phase 1 creates the `WorktreeEntry` model, the `GitStatusService+Worktree` list primitive, a new `WORKTREES` sidebar section, and "Open worktree in new window" / "Open in Terminal". Every later phase extends the same `GitStatusService+Worktree` surface and sidebar section with one action family plus focused integration tests against real temp Git repos.

**Tech Stack:** Swift 6, SwiftUI, XCTest, `xcodebuild`, existing `GitStatusService` + `GitCommandRunning`, local Git repositories created in tests.

**Design spec:** [docs/superpowers/specs/2026-06-20-worktree-management-design.md](../specs/2026-06-20-worktree-management-design.md)

---

## Plan Index

- Phase 1: [completed] [2026-06-20-worktree-phase-1-list-open.md](2026-06-20-worktree-phase-1-list-open.md) (branch: `codex/worktree-phase-1-list-open`)
- Phase 2: [completed] [2026-06-20-worktree-phase-2-label-store.md](2026-06-20-worktree-phase-2-label-store.md) (branch: `codex/worktree-phase-2-label-store`, merge: `0184c06`)
- Phase 3: [completed] [2026-06-20-worktree-phase-3-create-remove.md](2026-06-20-worktree-phase-3-create-remove.md) (branch: `codex/worktree-phase-3-create-remove`)
- Phase 4: [pending] 2026-06-20-worktree-phase-4-lock-prune-move-checkout.md

## Recommended Order

1. Finish Phase 1 first. It creates the model, the list primitive (`git worktree list --porcelain` parsing + parallel dirty counts), the sidebar section skeleton, and window-spawn wiring. Every later phase reuses these.
2. Do Phase 2 next. The label sidecar store is referenced by the Create sheet in Phase 3 (the sheet has a Label field), so the store must exist first.
3. Do Phase 3 after Phase 2. Create and Remove are the core CRUD lifecycle and depend on the label store for the Create sheet's Label field and for cleaning up labels on Remove.
4. Do Phase 4 last. Lock/Unlock, Prune, Move/Rename, and Switch Branch are independent finishing operations that all reuse the Phase 1 list + sidebar and the Phase 2 label store (Move updates the label sidecar key).

## Shared Rules for Every Phase

- Every worktree mutation posts `.repositoryDidChange` after the git command succeeds so the sidebar reloads.
- Every git op lives in `GitStatusService+Worktree.swift` as an async method and goes through `runGit(arguments:in:)` — no shelling out elsewhere.
- Destructive ops (`remove`, `move`, `checkout`) check a guard before running and surface a confirm alert on failure (pattern from Git Undo).
- The main worktree (repo root) is always listed by `git worktree list` and must be rendered as non-removable / non-lockable.
- Label state lives in the sidecar `.git/macgit/worktree-labels.json` (Phase 2+); git ops never touch the sidecar directly except `WorktreeLabelStore`.
- Dirty counts are fetched in parallel via `withTaskGroup`; a per-worktree status failure yields `dirtyCount = -1` (rendered as `?`).
- Integration tests create real temp Git repos with `git init`, drive `git worktree` via CLI `Process()` to set up state, then assert on `GitStatusService` methods. Temp dirs are cleaned up per test.

## Self-Review

Spec coverage:

- All 9 scoped operations are covered across the four phases: List/Open/Terminal (P1), Label (P2), Create/Remove (P3), Lock/Unlock/Prune/Move/Checkout (P4).
- The dependency order lets each phase ship working software: after P1 the user can see and open worktrees; after P2 they can label them; after P3 full CRUD; after P4 all 9 ops.

Placeholder scan:

- This roadmap links concrete plan filenames. Phase 1 has a full detailed plan file; Phases 2-4 are scoped here and get detailed plan files when ready to execute (same pattern as the Git Undo roadmap).

Type consistency:

- All phases extend the same Phase 1 types: `WorktreeEntry`, `GitStatusService+Worktree`, and the `WORKTREES` sidebar section. Phase 2 adds `WorktreeLabelStore`; Phase 3 reuses it; Phase 4 reuses all.
