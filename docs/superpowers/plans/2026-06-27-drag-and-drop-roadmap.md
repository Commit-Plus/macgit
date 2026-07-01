# Drag and Drop Git Actions Roadmap

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a safe subset of Tower-style drag-and-drop actions in three independently useful phases.

**Architecture:** A repository-scoped `GitDragPayload` and pure `GitDragDropPolicy` connect drag sources in History, File status, and the sidebar to confirmation requests owned by `MainWindowView`. Git execution remains in `GitStatusService`, and every successful mutation uses the existing undo, refresh, and `.repositoryDidChange` conventions.

**Tech Stack:** Swift, SwiftUI `Transferable`, SwiftUI drag/drop APIs, XCTest, real temporary Git repositories, `xcodebuild`.

**Design spec:** [2026-06-27-drag-and-drop-design.md](../specs/2026-06-27-drag-and-drop-design.md)

---

## Plan Index

- Phase 1: [completed] [2026-06-27-drag-and-drop-phase-1-commit-drag.md](2026-06-27-drag-and-drop-phase-1-commit-drag.md) (branch: `codex/drag-and-drop-phase-1-commit-drag`, landed on `main` at `517fa81`; Tasks 1-3 were merged earlier at `6494741`)
- Phase 2: [completed] [2026-06-27-drag-and-drop-phase-2-branch-drag.md](2026-06-27-drag-and-drop-phase-2-branch-drag.md) (branch: `codex/drag-and-drop-phase-2-branch-drag`, landed on `main` at `827b1a7`)
- Phase 3: [completed] [2026-06-27-drag-and-drop-phase-3-stash-drag.md](2026-06-27-drag-and-drop-phase-3-stash-drag.md) (branch: `codex/drag-and-drop-phase-3-stash-drag`, landed on `main` at `c3bbf88`)

## Recommended Order

1. Phase 1 establishes the shared payload, validation policy, History multi-selection, local-branch drop targets, confirmation UI, and batch cherry-pick undo.
2. Phase 2 extends those types and targets with local-branch sources, Merge/Rebase confirmation, and branch-based Create Branch preselection.
3. Phase 3 adds the independent File status and stash payloads after the shared infrastructure is proven.

Do not start a phase until every earlier phase is merged to `main`, committed, and passing the full test suite. Implement each phase in its own `.worktrees/drag-and-drop-phase-N-*` checkout on a `codex/drag-and-drop-phase-N-*` branch created from the latest `main`.

## Shared Rules

- A non-current commit target runs in an existing or temporary worktree after explicit cherry-pick confirmation; the open working copy is never switched.
- Commit actions accept any local branch; branch merge/rebase actions accept only the current branch.
- A drop opens confirmation; Git does not run from a hover or drop callback.
- Payload repository paths must match the receiving window's standardized repository path.
- Remote branches and merge-commit cherry-picks are rejected in v1.
- Current-working-copy Git actions register undo only after successful completion; worktree-only cherry-picks do not register a main-HEAD undo.
- Successful actions refresh `SyncState` and post `.repositoryDidChange`.
- Current-working-copy conflicts expose existing in-progress/conflict UI. Non-current cherry-pick conflicts retain and report their worktree path. Failed actions do not register undo.
- Use macOS 26 `dropDestination(for:isEnabled:action:)` and `onDropSessionUpdated(_:)`, not the deprecated targeted overload.
- Run focused tests during development and the full `xcodebuild ... test` command before marking a phase completed.
- Do not launch the app after build/test verification.

## Phase Outcomes

### After Phase 1

- Plain, Command, and Shift commit selection works in the custom History graph list.
- Dragging selected non-merge commits onto any local branch highlights that row and opens batch cherry-pick confirmation.
- Confirming a non-current target uses an existing or temporary worktree and leaves the open branch and working directory unchanged.
- Dragging one commit onto BRANCHES opens Create Branch with that commit selected.
- A completed current-branch batch cherry-pick has one guarded undo/redo entry.

### After Phase 2

- Non-current local branches are draggable.
- Dropping a local branch onto the current branch confirms Merge by default or Rebase when Option is held.
- Dropping a local branch onto BRANCHES opens Create Branch with that branch as the start point.
- Merge and rebase use existing guarded HEAD-changing undo behavior.

### After Phase 3

- Dragging a selected File status row carries the selected path set.
- Dropping files on STASHES confirms a path-scoped stash that includes only selected untracked files.
- Stash redo preserves the same path list.
- Dropping a stash on File status confirms Apply and retains the stash.

## Completion Checklist

- [x] Phase 1 merged to `main`, roadmap marker updated with merge commit, full tests green.
- [x] Phase 2 merged to `main`, roadmap marker updated with merge commit, full tests green.
- [x] Phase 3 merged to `main`, roadmap marker updated with merge commit, full tests green.
- [ ] Manual pointer-level QA verifies the commit preview follows the pointer, every local branch gets a dark hover highlight and label, dropping opens confirmation for that branch, and dimming clears after drop or cancel in light and dark mode.
- [ ] Remaining manual QA covers target labels, Option-drop, invalid targets, and VoiceOver labels.
