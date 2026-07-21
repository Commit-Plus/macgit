# Phase 5: Subtree Add, Pull, and Push Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add new subtrees and exchange changes with their configured remote branch using guarded, credential-aware `git subtree` operations.

**Architecture:** A capability checker and clean-parent policy fail before mutation. `GitStatusService+Subtree` runs credential-injected add/pull/push commands and writes registry metadata only after successful Add; `MainWindowView` owns confirmations, progress, credentials, and refresh.

**Tech Stack:** Swift 6, SwiftUI, XCTest, `git subtree`, existing Git credential injectors/provider accounts, real local bare repositories.

**Design spec:** [2026-07-13-submodule-subtree-design.md](../specs/2026-07-13-submodule-subtree-design.md)

## Global Constraints

- Follow [the roadmap constraints](2026-07-13-submodule-subtree-roadmap.md#global-constraints).
- Prerequisites: Phases 1-4 are merged and verified on `main`.
- Branch as `codex/submodule-subtree-phase-5-subtree-operations`.
- Add/Pull/Push never auto-commit beyond commits created by `git subtree` itself and never run when the parent working tree or index is dirty.

---

## File Structure

- Create `macgit/Services/GitStatusService+Subtree.swift`.
- Create `macgit/Models/SubtreeOperationPolicy.swift`.
- Modify `AddOrLinkSubtreeSheet.swift`, `SidebarSubtreeViews.swift`, `SidebarView.swift`, and `MainWindowView.swift`.
- Create `macgitTests/GitSubtreeCapabilityTests.swift`.
- Create `macgitTests/GitSubtreeOperationTests.swift`.
- Create `macgitTests/SubtreeOperationPolicyTests.swift`.
- Extend `GitCredentialInjectorTests.swift` to verify the shared credential-environment seam used by subtree operations.

## Task 1: Add Capability and Clean-Tree Policy

**Interfaces:**

```swift
enum SubtreeOperation: Equatable { case add, pull, push }

struct SubtreeOperationDecision: Equatable {
    let isAllowed: Bool
    let blockingPaths: [String]
    let message: String?
}

func supportsGitSubtree(in repositoryURL: URL) async -> Bool
func subtreeOperationDecision(in repositoryURL: URL) async throws -> SubtreeOperationDecision
```

- [x] Write failing tests for available/unavailable command through a recording runner, clean parent, staged file, modified file, untracked file, merge conflict, and deterministic blocking paths.
- [x] Preflight with `git subtree -h`; normalize its help exit behavior because some Git distributions return non-zero after printing usage.
- [x] Guard with `git status --porcelain=v1 -z` and block on any record in v1.
- [x] Use exact unavailable error: `This Git installation does not include git subtree.`
- [x] Run focused tests, implement, rerun to green, and commit `feat: validate subtree operation readiness`.

## Task 2: Implement Credential-Aware Add, Pull, and Push

**Interfaces:**

```swift
func addSubtree(
    _ request: SubtreeLinkRequest,
    in repositoryURL: URL,
    credentialResolver: GitProviderCredentialResolver?,
    registry: GitSubtreeRegistryProtocol
) async throws -> GitSubtreeEntry

func pullSubtree(
    _ entry: GitSubtreeEntry,
    in repositoryURL: URL,
    credentialResolver: GitProviderCredentialResolver?
) async throws

func pushSubtree(
    _ entry: GitSubtreeEntry,
    in repositoryURL: URL,
    credentialResolver: GitProviderCredentialResolver?
) async throws
```

- [x] Write local-bare-repository integration tests for Add with squash, Add without squash, Pull with upstream change, Push with prefix change, capability failure, dirty-tree rejection, command failure does not save registry, successful Add saves registry, and notification only after success.
- [x] Reuse the existing remote credential injection helpers; add no new token-bearing argument or URL rewriting.
- [ ] Execute:

```text
git subtree add --prefix=<path> <repository> <branch> [--squash]
git subtree pull --prefix=<path> <repository> <branch> [--squash]
git subtree push --prefix=<path> <repository> <branch>
```

- [x] Preserve argument boundaries exactly; never compose a shell command string.
- [x] Save registry after Add succeeds. Pull/Push never rewrite registry.
- [x] Post `.repositoryDidChange` after every successful Add, Pull, or Push so all repository-scoped consumers use one refresh path.
- [x] Run focused tests, implement, rerun to green, and commit `feat: run subtree network operations`.

## Task 3: Complete Add/Pull/Push UI

- [x] Enable `Add new subtree` mode in `AddOrLinkSubtreeSheet`; default to Add, keep Link selectable, and default `Squash imported history` on.
- [x] Existing remote names and a raw URL are accepted; branch and relative path are required.
- [x] Add context actions `Pull from Subtree Remote...` and `Push to Subtree Remote...` only when `folderExists`.
- [x] Pull confirmation states source repository/branch, destination prefix, and squash policy.
- [x] Push confirmation states that commits affecting the prefix will be split and sent to the configured repository/branch.
- [x] Route operations through `MainWindowView` with provider credentials and immediate progress labels: `Adding subtree...`, `Pulling <name>...`, and `Pushing <name>...`.
- [x] On a dirty-tree guard, list up to five blocking paths plus a remaining-count suffix; do not start Git.
- [x] Keep sheets/confirmations open on recoverable failure and sanitize error output.
- [x] Run all Phase 5 focused tests and build; commit `feat: add subtree operation UI`.

## Task 4: Final Verification and Roadmap Completion

- [x] Run all subtree and credential focused tests:

```bash
rtk xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitSubtreeCapabilityTests -only-testing:macgitTests/GitSubtreeOperationTests -only-testing:macgitTests/SubtreeOperationPolicyTests -only-testing:macgitTests/GitCredentialInjectorTests
```

- [x] Run the complete suite once and build:

```bash
rtk xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS'
rtk xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```
- [ ] Perform manual QA with one HTTPS and one SSH remote, light/dark mode, Add cancel/failure, Pull conflict, Push rejection, stale link, and credential error copy. Do not launch the app automatically; manual QA is user-driven.
- [x] Merge to `main`, verify, mark Phase 5 `[completed]`, and complete the roadmap checklist only for evidence actually observed. Merged at `ce1992a`; merge-step build/test reruns were explicitly waived.
