# Submodule and Subtree Management Roadmap

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver SourceTree-inspired submodule and subtree management in five independently testable phases.

**Architecture:** Standard Git metadata drives submodules, while a local `commitplus-subtree.*` Git config registry drives subtrees. `SidebarView` renders both sections and delegates operations through `MainWindowView`; Git parsing, mutation, capability checks, credential environments, and refresh notifications remain in focused services.

**Tech Stack:** Swift 6, SwiftUI, AppKit, XCTest, real temporary Git repositories, `git submodule`, `git subtree`, existing `GitStatusService`, `GitProviderCredentialResolver`, and `xcodebuild`.

**Design spec:** [2026-07-13-submodule-subtree-design.md](../specs/2026-07-13-submodule-subtree-design.md)

## Global Constraints

- Do not launch Commit+ during verification.
- Every new `.swift` file starts with the repository AGPL v3 header required by `AGENTS.md`.
- Git execution stays in `GitStatusService` extensions; `SidebarView` does not run `Process()` or resolve credentials.
- Credentials never appear in command arguments, logs, subtree registry values, or UI error copy.
- Mutations never auto-commit.
- Post `.repositoryDidChange` only after a mutation succeeds.
- Use focused tests, then the complete macOS test suite for non-trivial changes, then `xcodebuild ... build`. Do not rerun a full suite that exits during bootstrap with the documented early-exit/abort failure.
- Start every phase from clean, current `main` on the phase branch listed below. Do not start a later phase until all prerequisites are merged to `main` and verified.

---

## Plan Index

- Phase 1: [completed] [2026-07-13-submodule-subtree-phase-1-submodule-discovery.md](2026-07-13-submodule-subtree-phase-1-submodule-discovery.md) (branch: `codex/submodule-subtree-phase-1-submodule-discovery`, landed on `main` at `37aaad7`)
- Phase 2: [completed] [2026-07-13-submodule-subtree-phase-2-submodule-safe-actions.md](2026-07-13-submodule-subtree-phase-2-submodule-safe-actions.md) (branch: `codex/submodule-subtree-phase-2-submodule-safe-actions`, landed on `main` at `d4a202a`)
- Phase 3: [completed] [2026-07-13-submodule-subtree-phase-3-submodule-lifecycle.md](2026-07-13-submodule-subtree-phase-3-submodule-lifecycle.md) (branch: `codex/submodule-subtree-phase-3-submodule-lifecycle`, landed on `main` at `87e5ba7`)
- Phase 4: [completed] [2026-07-13-submodule-subtree-phase-4-subtree-registry.md](2026-07-13-submodule-subtree-phase-4-subtree-registry.md) (branch: `codex/submodule-subtree-phase-4-subtree-registry`, landed on `main` at `d5ee388`)
- Phase 5: [in progress] [2026-07-13-submodule-subtree-phase-5-subtree-operations.md](2026-07-13-submodule-subtree-phase-5-subtree-operations.md) (branch: `codex/submodule-subtree-phase-5-subtree-operations`)

## Recommended Order

1. Phase 1 establishes the standard submodule model, parser, lazy sidebar section, stable selection, and open/Finder/Terminal actions.
2. Phase 2 adds non-destructive and additive submodule actions: Add, Initialize, Update to Recorded Commit, Update from Remote, and Synchronize URL.
3. Phase 3 adds configuration and destructive lifecycle actions only after status/guards are proven: edit URL/branch, Deinitialize, and Remove.
4. Phase 4 starts subtree support with the local registry, Link Existing flow, stale-link handling, and read-only sidebar actions. It has no network mutation.
5. Phase 5 adds subtree capability preflight, Add, Pull, and Push with clean-tree guards and existing provider credential integration.

## Shared UI Rules

- Use exact section titles `SUBMODULES` and `SUBTREES`.
- A visible empty section shows `No submodules` or `No subtrees` and retains its `+` action.
- The existing `Show Submodules` / `Show Subtrees` settings remain visibility preferences; successful Add/Link enables the matching preference.
- Section expansion persists per repository with backward-compatible defaults of expanded.
- Single click selects; double click opens only initialized submodules. Subtrees do not open as separate repositories.
- Context menus are state-aware and do not expose actions that cannot run in the current state.
- Async row/header actions show progress through `onRunRepositoryOperation` immediately.

## Shared Service Rules

- All repository-relative paths are validated and standardized before reaching Git.
- Network calls accept `GitProviderCredentialResolver?` and reuse existing HTTPS askpass/SSH environment construction.
- A command failure never registers subtree metadata, dismisses a corrective sheet, or reports success.
- Registry unlink never removes working-tree files.
- Submodule deinitialize and repository removal use different confirmation copy and service methods.

## Phase Outcomes

### After Phase 1

- Existing submodules appear with path, branch, and accurate initialized/dirty/new-commit/missing/conflict state.
- Initialized submodules can open in Commit+, Finder, or Terminal.
- The section is lazy-loaded, refreshes after repository changes, and preserves selection.

### After Phase 2

- Users can add a submodule without Commit+ committing it.
- Uninitialized submodules can initialize.
- Users can update to the superproject's recorded commit or explicitly update from the configured remote branch.
- URL synchronization is available as a separate safe action.

### After Phase 3

- URL and branch settings can be edited with validation.
- Users can deinitialize a local checkout without removing repository metadata.
- Users can remove a submodule with dirty-state confirmation and an explicit force path.

### After Phase 4

- Users can register/link an existing subtree directory without mutating history.
- Registered subtrees survive relaunch via local Git config and show stale/missing-folder state.
- Users can edit or unlink registry metadata without deleting files.

### After Phase 5

- Users can add, pull, and push registered subtrees.
- Git subtree availability and clean-parent-tree guards fail early with actionable messages.
- HTTPS/SSH remote access uses connected provider credentials without exposing secrets.

## Completion Checklist

- [x] Phase 1 merged to `main` at `37aaad7`; focused tests and build verified on the phase branch. The full-suite attempt hit the documented test-host bootstrap abort and was not rerun.
- [x] Phase 2 merged to `main` at `d4a202a`; focused tests and build verified, and the full test-host bootstrap crash was hit again on the focused test pass so it was not rerun.
- [x] Phase 3 merged to `main` at `87e5ba7`; focused sidebar policy tests and build verified on `main`. The full-suite attempt hit the documented test-host bootstrap abort and was not rerun.
- [x] Phase 4 merged to `main` at `d5ee388`; focused registry/link/sidebar policy tests and build verified. The full-suite attempt hit the documented test-host bootstrap abort and was not rerun.
- [ ] Phase 5 merged to `main`; focused tests, full tests, and build verified.
- [ ] Manual QA covers light/dark mode, collapsed/expanded persistence, empty states, all confirmation copy, and cancellation behavior.
- [ ] Manual QA verifies no operation launches a duplicate app instance and no credential appears in progress/error output.
