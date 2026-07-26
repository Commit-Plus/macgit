# SidebarView Refactor Roadmap

**Design:** [`docs/superpowers/specs/2026-07-26-sidebar-view-refactor-design.md`](../specs/2026-07-26-sidebar-view-refactor-design.md)

**Goal:** Split the 3,596-line `SidebarView.swift` into focused SwiftUI components and behavior-oriented orchestration extensions while preserving its external API and runtime behavior.

## Global Constraints

- Preserve the current `SidebarView` initializer and `MainWindowView` callback contract.
- Preserve visible layout, copy, menus, disabled states, selection, gestures, drag/drop, lazy loading, and refresh behavior.
- Keep Git execution in `GitStatusService` and shared repository-operation ownership in `MainWindowView`.
- Keep branch-list cache behavior unchanged: two-minute TTL and no implicit network fetch.
- Every new Swift file starts with the repository AGPL v3 header.
- Do not launch the application. Verification ends with focused tests and a successful macOS build.
- Implement each phase on a clean `codex/<phase>` branch created from `main`; never implement a phase directly on `main`.

## Phases

| Phase | Scope | Status | Plan |
| --- | --- | --- | --- |
| 1 | Models, policies, section header, workspace section | [completed] | [`2026-07-26-sidebar-view-refactor-phase-1-foundation.md`](2026-07-26-sidebar-view-refactor-phase-1-foundation.md) |
| 2 | Branches, tags, remotes, and stashes components | [completed] | [`2026-07-26-sidebar-view-refactor-phase-2-core-sections.md`](2026-07-26-sidebar-view-refactor-phase-2-core-sections.md) |
| 3 | Worktrees, submodules, subtrees, sheets, and presentation | [pending] | [`2026-07-26-sidebar-view-refactor-phase-3-specialized-sections.md`](2026-07-26-sidebar-view-refactor-phase-3-specialized-sections.md) |
| 4 | Loading, drag/drop, action extensions, root cleanup, final verification | [pending] | [`2026-07-26-sidebar-view-refactor-phase-4-orchestration.md`](2026-07-26-sidebar-view-refactor-phase-4-orchestration.md) |

## Phase Boundaries

- Phase 1 is a mechanical foundation and must leave all feature rendering in `SidebarView`.
- Phase 2 extracts the high-frequency branch/tag/remote/stash interactions without moving repository lifecycle tasks.
- Phase 3 extracts specialized sections and presentation while retaining root-owned state.
- Phase 4 moves behavior into cross-file extensions only after component interfaces have stabilized.
- Each phase must build successfully before it is merged and before the next branch is created from updated `main`.

## Completion

The roadmap is complete when all four phase rows are marked `[completed]`, every phase commit is merged to `main`, focused sidebar tests pass or have a documented test-host bootstrap failure, and the final macOS build succeeds.
