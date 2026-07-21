# Phase 4: Subtree Registry and Link Existing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Register existing subtree directories in repository-local Commit+ metadata and display/manage those links without running history-changing subtree commands.

**Architecture:** `GitSubtreeRegistry` stores validated entries in local Git config using `commitplus-subtree.<id>.*`. The sidebar loads entries lazily and exposes Finder, Terminal, Edit Link, and metadata-only Unlink actions; no add/pull/push operation exists until Phase 5.

**Tech Stack:** Swift 6, SwiftUI, AppKit, XCTest, `git config --local`, existing sidebar state and window operation patterns.

**Design spec:** [2026-07-13-submodule-subtree-design.md](../specs/2026-07-13-submodule-subtree-design.md)

## Global Constraints

- Follow [the roadmap constraints](2026-07-13-submodule-subtree-roadmap.md#global-constraints).
- Prerequisites: Phases 1-3 are merged and verified on `main`.
- Branch as `codex/submodule-subtree-phase-4-subtree-registry`.
- Registry metadata is local and untracked. Unlink never deletes files.

---

## File Structure

- Create `macgit/Models/GitSubtreeEntry.swift`.
- Create `macgit/Services/GitSubtreeRegistry.swift`.
- Create `macgit/Views/MainWindow/SidebarSubtreeViews.swift`.
- Create `macgit/Views/MainWindow/AddOrLinkSubtreeSheet.swift` with Phase 4 restricted to Link mode.
- Modify `SidebarSettingsStore.swift`, `SidebarView.swift`, `MainWindowView.swift`, `ToolbarAction.swift`, and `macgitApp.swift`.
- Create `macgitTests/GitSubtreeRegistryTests.swift`.
- Create `macgitTests/SubtreeLinkValidationTests.swift`.
- Create `macgitTests/SubtreeSidebarPolicyTests.swift`.

## Task 1: Define Entry and Registry Encoding

**Interfaces:**

```swift
struct GitSubtreeEntry: Identifiable, Equatable {
    let id: String
    var name: String
    var path: String
    var repository: String
    var branch: String
    var squash: Bool
    var folderExists: Bool
}

protocol GitSubtreeRegistryProtocol {
    func entries(in repositoryURL: URL) async throws -> [GitSubtreeEntry]
    func save(_ entry: GitSubtreeEntry, in repositoryURL: URL) async throws
    func remove(id: String, in repositoryURL: URL) async throws
}
```

- [x] Write failing tests for empty registry, round-trip, deterministic ordering by path, stable ID generation, collision suffix, incomplete entry omission, duplicate/overlapping path rejection, stale folder, edit, and removal.
- [x] Store only these keys:

```text
commitplus-subtree.<id>.name
commitplus-subtree.<id>.path
commitplus-subtree.<id>.repository
commitplus-subtree.<id>.branch
commitplus-subtree.<id>.squash
```

- [x] Use `git config --local --null --get-regexp '^commitplus-subtree\.'` for reads and `git config --local` for writes/removals. Do not parse `.git/config` directly because linked worktrees may use a `.git` file.
- [x] Run focused tests, implement, rerun to green, and commit `feat: add local subtree registry`.

## Task 2: Validate and Link Existing Directories

**Interfaces:**

```swift
struct SubtreeLinkRequest: Equatable {
    var name: String
    var repository: String
    var branch: String
    var path: String
    var squash: Bool
}

func linkExistingSubtree(
    _ request: SubtreeLinkRequest,
    in repositoryURL: URL,
    registry: GitSubtreeRegistryProtocol
) async throws -> GitSubtreeEntry
```

- [x] Write failing validation tests for required fields, absolute/escaping path, symlink escape, missing directory, untracked directory, duplicate/overlap, and valid tracked directory.
- [x] Validate tracking with `git ls-files --error-unmatch -- <path>` and require at least one tracked path under the prefix.
- [x] Saving a link performs no fetch, merge, commit, or working-tree write.
- [x] Post `.repositoryDidChange` only after registry save succeeds.
- [x] Run focused tests, implement, rerun to green, and commit `feat: link existing subtree directories`.

## Task 3: Add Read-Only Subtree Sidebar and Link UI

- [x] Add `SidebarSelection.subtree(String)` using registry ID.
- [x] Add `subtreesExpanded: Bool = true` with backward-compatible decoding and toggle handling.
- [x] Replace `Coming soon` with a lazy-loaded section, header `+`, loading state, `No subtrees`, row subtitle, `Squashed`, and `Missing folder` badge.
- [x] `SubtreeSidebarPolicy` exposes Finder/Terminal only when the folder exists, and always exposes Edit Link/Unlink.
- [x] Add Link mode fields from the design. Keep `Add new subtree` visible but disabled with help `Available in Phase 5`, so the next phase removes only the disabled state.
- [x] Add `Actions > Add/Link Subtree...`; in Phase 4 it opens Link mode.
- [x] Add confirmation copy: `Unlink removes Commit+ metadata only. Files under <path> remain unchanged.`
- [x] Successful Link enables `appState.showSubtrees`; successful Unlink keeps files and clears selection if needed.
- [x] Run policy/settings/registry tests and build; commit `feat: show linked subtrees in sidebar`.

## Task 4: Verification and Roadmap Handoff

- [x] Run all Phase 4 focused tests:

```bash
rtk xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitSubtreeRegistryTests -only-testing:macgitTests/SubtreeLinkValidationTests -only-testing:macgitTests/SubtreeSidebarPolicyTests
```

- [x] Run the complete suite once and build:

```bash
rtk xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS'
rtk xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```
- [x] Merge to `main`, verify, then mark Phase 4 `[completed]` with the landed commit.

## Completion Notes

- Landed on `main` at `d5ee388`.
- Focused tests passed:
  `rtk xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitSubtreeRegistryTests -only-testing:macgitTests/SubtreeLinkValidationTests -only-testing:macgitTests/SubtreeSidebarPolicyTests`
- Full-suite attempt:
  `rtk xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS'`
  stopped with the documented test-host bootstrap abort (`Early unexpected exit` / `abort() called`) and was not rerun.
- Build passed:
  `rtk xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`
