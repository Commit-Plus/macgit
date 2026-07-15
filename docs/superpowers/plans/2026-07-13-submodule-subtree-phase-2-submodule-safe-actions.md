# Phase 2: Safe Submodule Actions Implementation Plan

**Status:** completed; merged to `main` at `d4a202a`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add, initialize, update, and synchronize submodules without automatic commits or destructive removal.

**Architecture:** Validated request models feed credential-aware `GitStatusService+Submodule` methods. `MainWindowView` supplies credentials and progress; focused sheets/context menus collect intent and reload the existing Phase 1 section after success.

**Tech Stack:** Swift 6, SwiftUI, XCTest, `git submodule add/init/update/sync`, existing provider credential injectors and repository progress UI.

**Design spec:** [2026-07-13-submodule-subtree-design.md](../specs/2026-07-13-submodule-subtree-design.md)

## Global Constraints

- Follow [the roadmap constraints](2026-07-13-submodule-subtree-roadmap.md#global-constraints).
- Prerequisite: Phase 1 is merged and verified on `main`.
- Branch as `codex/submodule-subtree-phase-2-submodule-safe-actions`.
- Do not implement set-url, set-branch, deinitialize, or remove in this phase.

---

## File Structure

- Create `macgit/Models/SubmoduleRequests.swift`.
- Modify `macgit/Services/GitStatusService+Submodule.swift`.
- Create `macgit/Views/MainWindow/AddSubmoduleSheet.swift`.
- Modify `macgit/Views/MainWindow/SidebarSubmoduleViews.swift`.
- Modify `macgit/Views/MainWindow/SidebarView.swift` and `MainWindowView.swift`.
- Modify `macgit/App/ToolbarAction.swift` and `macgit/App/macgitApp.swift` for `Actions > Add Submodule...`.
- Create `macgitTests/SubmoduleRequestValidationTests.swift`.
- Create `macgitTests/GitSubmoduleSafeActionTests.swift`.
- Extend `macgitTests/SubmoduleSidebarPolicyTests.swift`.

## Task 1: Add Request Validation

**Interfaces:**

- `SubmoduleAddRequest(repository: String, path: String, branch: String?, initializeAfterAdd: Bool, shallow: Bool)`.
- `SubmoduleUpdateMode { case recordedCommit, remoteCheckout }`.
- `SubmoduleRequestValidator.validate(addRequest:in:) throws -> SubmoduleAddRequest` returns trimmed, standardized input.

- [ ] Write failing tests for empty URL, absolute path, `..` escape, symlink escape, duplicate configured path, trimmed branch, and valid nested relative path.
- [ ] Run `rtk xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/SubmoduleRequestValidationTests`; expect missing-type failures.
- [ ] Implement validation with standardized repository containment and `/` separators.
- [ ] Rerun the focused tests; expect all pass.
- [ ] Commit as `feat: validate submodule action requests`.

## Task 2: Add Credential-Aware Safe Service Actions

**Interfaces:**

```swift
func addSubmodule(
    _ request: SubmoduleAddRequest,
    in repositoryURL: URL,
    credentialResolver: GitProviderCredentialResolver?
) async throws

func initializeSubmodule(
    path: String,
    in repositoryURL: URL,
    credentialResolver: GitProviderCredentialResolver?
) async throws

func updateSubmodule(
    path: String,
    mode: SubmoduleUpdateMode,
    in repositoryURL: URL,
    credentialResolver: GitProviderCredentialResolver?
) async throws

func synchronizeSubmoduleURL(path: String, in repositoryURL: URL) async throws
```

- [ ] Write real-repository tests for add/default branch, add/specific branch, add/shallow arguments through a recording runner seam, initialize after fresh clone, update to recorded commit, remote update, URL sync, command failure, and notification only after success.
- [ ] Run focused tests and confirm failures for missing methods.
- [ ] Move `credentialInjection(for:in:credentialResolver:credentialInjector:sshCredentialInjector:)` and `runRemoteGit(arguments:in:injection:)` from the private scope in `GitStatusService+Remote.swift` to internal methods in `GitStatusService+RemoteCredential.swift`, then reuse those exact methods; do not duplicate askpass or SSH construction.
- [ ] Implement commands:

```text
git submodule add [--branch <branch>] [--depth 1] -- <repository> <path>
git submodule update --init -- <path>
git submodule update --checkout -- <path>
git submodule update --remote --checkout -- <path>
git submodule sync -- <path>
```

- [ ] When `initializeAfterAdd == false`, run `git submodule deinit -f -- <path>` immediately after successful Add. Verify in the integration test that `.gitmodules` and the gitlink remain staged while the child checkout is uninitialized.
- [ ] Rerun focused tests; expect pass and no credential values in recorded arguments.
- [ ] Commit as `feat: add safe submodule operations`.

## Task 3: Add Sheet, Menus, and Actions Menu Entry

**Interfaces:**

- `ToolbarAction.addSubmodule` posts through the existing `.toolbarAction` notification.
- `SidebarView` exposes `onRequestAddSubmodule`, `onRequestInitializeSubmodule`, `onRequestUpdateSubmodule`, and `onRequestSynchronizeSubmoduleURL` callbacks.

- [ ] Extend policy tests so Add is header/background-only, Initialize appears only for uninitialized entries, both Update actions appear only for initialized entries, and Synchronize URL appears for configured entries.
- [ ] Build `AddSubmoduleSheet` with exact labels from the design, inline validation error, Cancel/Add buttons, Add disabled while invalid/running, and repository-relative folder selection.
- [ ] Replace the disabled Phase 1 header `+` with `Add Submodule`.
- [ ] Add `Actions > Add Submodule...`, disabled without an open repository.
- [ ] Route network callbacks through `MainWindowView` with `providerAccountController.credentialResolver()` and `runRepositoryOperation`.
- [ ] On success: enable `appState.showSubmodules`, dismiss, refresh through `.repositoryDidChange`, and preserve the new row selection. On failure: keep the sheet open and show sanitized inline error.
- [ ] Run policy/request/service focused tests and `rtk xcodebuild ... build`; expect pass.
- [ ] Commit as `feat: add submodule action UI`.

## Task 4: Verification and Roadmap Handoff

- [x] Run focused tests:

```bash
rtk xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/SubmoduleRequestValidationTests -only-testing:macgitTests/GitSubmoduleSafeActionTests -only-testing:macgitTests/SubmoduleSidebarPolicyTests
```

- [x] Run the complete suite once, then build:

```bash
rtk xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS'
rtk xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```
- [x] Merge to `main`, verify there, and only then mark Phase 2 `[completed]` with the landed commit.
