# Phase 3: Submodule Configuration and Destructive Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Edit submodule URL/branch settings, deinitialize local checkouts, and remove submodules with explicit dirty-state guards.

**Architecture:** A pure lifecycle policy separates safe configuration, local deinitialization, and repository removal. Service methods validate expected state immediately before mutation; SwiftUI sheets/alerts use distinct copy so users cannot confuse deinitializing a checkout with removing tracked metadata.

**Tech Stack:** Swift 6, SwiftUI, XCTest, `git submodule set-url`, `set-branch`, `deinit`, `git rm`, existing credential and notification infrastructure.

**Design spec:** [2026-07-13-submodule-subtree-design.md](../specs/2026-07-13-submodule-subtree-design.md)

## Global Constraints

- Follow [the roadmap constraints](2026-07-13-submodule-subtree-roadmap.md#global-constraints).
- Prerequisites: Phases 1 and 2 are merged and verified on `main`.
- Branch as `codex/submodule-subtree-phase-3-submodule-lifecycle`.
- Repository removal never commits and never silently discards child changes.

---

## File Structure

- Create `macgit/Models/SubmoduleLifecyclePolicy.swift`.
- Modify `macgit/Services/GitStatusService+Submodule.swift`.
- Create `macgit/Views/MainWindow/EditSubmoduleSheet.swift`.
- Modify `macgit/Views/MainWindow/SidebarSubmoduleViews.swift`, `SidebarView.swift`, and `MainWindowView.swift`.
- Create `macgitTests/SubmoduleLifecyclePolicyTests.swift`.
- Create `macgitTests/GitSubmoduleLifecycleTests.swift`.

## Task 1: Define Lifecycle Guards and Confirmation Copy

**Interfaces:**

```swift
enum SubmoduleLifecycleAction: Equatable {
    case editSettings
    case deinitialize(force: Bool)
    case remove(force: Bool)
}

struct SubmoduleLifecycleDecision: Equatable {
    let isAllowed: Bool
    let requiresConfirmation: Bool
    let message: String?
}
```

- [x] Write failing policy tests for clean initialized, dirty initialized, uninitialized, missing, and conflict entries.
- [x] Require confirmation for every deinitialize/remove operation; require explicit force for dirty/conflict child working trees.
- [x] Use exact distinctions in copy: `Deinitialize` says local checkout files are removed while `.gitmodules` and the recorded gitlink remain; `Remove Submodule` says the path and `.gitmodules` entry are staged for removal.
- [x] Run focused policy tests, implement the pure policy, rerun to green, and commit `feat: define submodule lifecycle guards`.

## Task 2: Implement Configuration and Lifecycle Services

**Interfaces:**

```swift
func updateSubmoduleSettings(
    path: String,
    url: String,
    branch: String?,
    in repositoryURL: URL
) async throws

func deinitializeSubmodule(
    path: String,
    force: Bool,
    in repositoryURL: URL
) async throws

func removeSubmodule(
    path: String,
    force: Bool,
    in repositoryURL: URL
) async throws
```

- [x] Write integration tests for set URL, set branch, clear branch to default, clean deinitialize, dirty deinitialize rejection, forced deinitialize, clean removal, dirty removal rejection, forced removal, `.gitmodules` cleanup, and notification only after success.
- [x] Before deinitialize/remove, re-read child status instead of trusting stale sidebar state.
- [x] Implement:

```text
git submodule set-url -- <path> <url>
git submodule set-branch --branch <branch> -- <path>
git submodule set-branch --default -- <path>
git submodule deinit [--force] -- <path>
git rm [-f] -- <path>
```

- [x] After `git rm`, remove an empty `.gitmodules` file with Git-aware staging only when no submodule sections remain. Do not manually delete `.git/modules/<name>` in v1.
- [x] Rerun focused tests to green and commit `feat: manage submodule lifecycle`.

## Task 3: Add Settings Sheet and Destructive UI

- [x] Extend sidebar policy tests for exact action availability.
- [x] Add `EditSubmoduleSheet` with `Repository URL`, optional `Branch`, Cancel/Save, validation, and inline error.
- [x] Add context actions `Edit Submodule Settings...`, `Deinitialize...`, and `Remove Submodule...` with destructive roles only where appropriate.
- [x] Add separate confirmation presentations; never reuse one generic destructive alert.
- [x] Route execution through `MainWindowView` progress and refresh callbacks. Preserve selection for Edit/Deinitialize; move selection to File status after successful Remove.
- [x] Verify policy/service tests and build; commit `feat: add submodule lifecycle UI`.

## Task 4: Verification and Roadmap Handoff

- [x] Run Phase 3 focused tests:

```bash
rtk xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/SubmoduleLifecyclePolicyTests -only-testing:macgitTests/GitSubmoduleLifecycleTests -only-testing:macgitTests/SubmoduleSidebarPolicyTests
```

- [x] Run the complete suite once and build:

```bash
rtk xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS'
rtk xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```
- [x] Merge to `main`, verify, then mark Phase 3 `[completed]` with the landed commit.

Result: Phase 3 landed on `main` at `87e5ba7`. `SubmoduleSidebarPolicyTests` and the final build passed on `main`; the focused lifecycle/full-suite commands hit the documented test-host bootstrap abort and were not rerun.
