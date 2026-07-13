# Phase 1: Submodule Discovery and Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Discover existing Git submodules, show accurate state in `SUBMODULES`, and open initialized submodules in Commit+, Finder, or Terminal.

**Architecture:** A pure parser combines `.gitmodules`, index gitlinks, and `git submodule status` into `GitSubmoduleEntry`. `GitStatusService+Submodule` owns command execution; sidebar policy and focused views render state while `MainWindowView` owns window/AppKit actions.

**Tech Stack:** Swift 6, SwiftUI, AppKit, XCTest, `git config`, `git ls-files`, `git submodule status`, existing repository notifications.

**Design spec:** [2026-07-13-submodule-subtree-design.md](../specs/2026-07-13-submodule-subtree-design.md)

## Global Constraints

- Follow [the roadmap constraints](2026-07-13-submodule-subtree-roadmap.md#global-constraints).
- Branch from clean `main` as `codex/submodule-subtree-phase-1-submodule-discovery`.
- This phase is read-only. Do not add, initialize, update, edit, deinitialize, or remove submodules.

---

## Prerequisites

None. This is the first phase.

## Implementation Status

- Task 1 completed at `7cb36bf`: parser tests passed after the expected missing-type red state.
- Task 2 completed at `721c4c6`, with empty-`.gitmodules` hardening added in the final review: seven real-repository discovery tests pass after their expected red states.
- Task 3 completed at `42b4bd1`: sidebar policy/settings tests passed and the macOS build exited successfully.
- Task 4 verification on the phase branch: the combined focused Phase 1 suite passed and the macOS build succeeded. The one permitted full-suite attempt ended during test-host bootstrap with `Early unexpected exit` / `abort() called`; per `AGENTS.md`, it was not rerun.
- Pending: merge the phase branch to `main`, verify the merged checkout, then mark Phase 1 `[completed]` in the roadmap.

## File Structure

- Create `macgit/Models/GitSubmoduleEntry.swift`: model and state enum.
- Create `macgit/Services/GitSubmoduleParser.swift`: deterministic parser for command outputs.
- Create `macgit/Services/GitStatusService+Submodule.swift`: discovery commands and status aggregation.
- Create `macgit/Models/SubmoduleSidebarAction.swift`: read-only sidebar action identifiers.
- Create `macgit/Services/SubmoduleSidebarPolicy.swift`: pure action availability policy.
- Create `macgit/Views/MainWindow/SidebarSubmoduleRow.swift`: accessible submodule row and context menu.
- Modify `macgit/Services/SidebarSettingsStore.swift`: persisted expansion state.
- Modify `macgit/Views/MainWindow/SidebarView.swift`: state, lazy load, section, selection, refresh.
- Modify `macgit/Views/MainWindow/MainWindowView.swift`: open/Finder/Terminal callbacks.
- Create `macgitTests/GitSubmoduleParserTests.swift`.
- Create `macgitTests/GitSubmoduleDiscoveryTests.swift`.
- Create `macgitTests/SubmoduleSidebarPolicyTests.swift`.

## Task 1: Define the Submodule Model and Parser

**Interfaces:**

- Produces `enum GitSubmoduleState: Equatable { case clean, modified, newCommits, uninitialized, missing, conflict }`.
- Produces `struct GitSubmoduleEntry: Identifiable, Equatable` with `name`, `path`, `url`, `branch`, `recordedCommit`, `checkedOutCommit`, `state`, and `isInitialized`.
- Produces `GitSubmoduleParser.parse(config:index:status:) throws -> [GitSubmoduleEntry]`.

- [ ] **Step 1: Write failing parser tests**

Create table-driven tests for these exact cases: initialized clean (` ` prefix), uninitialized (`-`), checked-out commit differs (`+`), conflict (`U`), configured entry missing from status, relative URL preservation, branch parsing, nested path, and malformed config missing `path` or `url`.

Use NUL-separated config fixtures matching:

```text
submodule.SharedKit.path\nPackages/SharedKit\0submodule.SharedKit.url\n../SharedKit.git\0submodule.SharedKit.branch\nmain\0
```

`git config -z` separates each key from its value with a newline and terminates each record with NUL; tests must preserve those exact bytes.

Use index fixtures matching `160000 <sha> 0\tPackages/SharedKit` and status fixtures matching `<prefix><sha> Packages/SharedKit (heads/main)`.

- [ ] **Step 2: Run the parser tests and confirm red**

Run:

```bash
rtk xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitSubmoduleParserTests
```

Expected: compilation fails because `GitSubmoduleParser` and `GitSubmoduleEntry` do not exist.

- [ ] **Step 3: Implement the model and parser**

Parsing rules:

- Key entries by configured relative path, never by display name.
- Normalize path separators to `/` but do not resolve them to absolute paths in the model.
- Use the index gitlink as `recordedCommit`.
- Map `-`, `+`, `U`, and space prefixes before doing secondary working-tree checks.
- Throw one parser error only for structurally unusable output; omit incomplete named config blocks while returning valid siblings.

- [ ] **Step 4: Run parser tests and confirm green**

Run the same focused command. Expected: all `GitSubmoduleParserTests` pass.

- [ ] **Step 5: Commit the parser slice**

```bash
rtk git add macgit/Models/GitSubmoduleEntry.swift macgit/Services/GitSubmoduleParser.swift macgitTests/GitSubmoduleParserTests.swift
rtk git commit -m "feat: parse submodule metadata and status"
```

## Task 2: Add Read-Only Submodule Discovery

**Interfaces:**

- Consumes `GitSubmoduleParser.parse(config:index:status:)`.
- Produces `GitStatusService.submodules(in repositoryURL: URL) async throws -> [GitSubmoduleEntry]`.

- [ ] **Step 1: Write failing real-repository discovery tests**

Build a parent repo and local child bare remote in temporary directories. Cover no `.gitmodules`, initialized child, uninitialized child after a fresh clone, child working-tree modification, child HEAD advancement, and a missing checkout directory.

- [ ] **Step 2: Verify discovery tests fail**

```bash
rtk xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitSubmoduleDiscoveryTests
```

Expected: compilation fails for missing `submodules(in:)`.

- [ ] **Step 3: Implement discovery commands**

Run these commands through `runGit`:

```text
git config -z --file .gitmodules --list
git ls-files --stage
git submodule status --recursive
```

Treat a missing `.gitmodules` file as `[]`. For initialized entries, run targeted `git status --porcelain` and `git rev-parse HEAD` in the child directory to distinguish clean and modified without changing it.

- [ ] **Step 4: Run discovery tests and confirm green**

Run the focused command. Expected: all discovery tests pass without network access.

- [ ] **Step 5: Commit the service slice**

```bash
rtk git add macgit/Services/GitStatusService+Submodule.swift macgitTests/GitSubmoduleDiscoveryTests.swift
rtk git commit -m "feat: discover repository submodules"
```

## Task 3: Add Sidebar State, Policy, and UI

**Interfaces:**

- Produces `SidebarSelection.submodule(String)` where the value is relative path.
- Produces `SubmoduleSidebarPolicy.actions(for:) -> Set<SubmoduleSidebarAction>`; Phase 1 returns only `.openInCommitPlus`, `.showInFinder`, and `.openInTerminal` for initialized, existing entries.
- Adds `submodulesExpanded: Bool = true` to `SidebarSectionState` with backward-compatible decoding.

- [ ] **Step 1: Write failing settings and policy tests**

Assert old JSON decodes with `submodulesExpanded == true`. Assert initialized entries expose all three read-only actions; uninitialized/missing entries expose none.

- [ ] **Step 2: Verify focused tests fail**

```bash
rtk xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/SubmoduleSidebarPolicyTests -only-testing:macgitTests/SidebarViewStashTests
```

- [ ] **Step 3: Implement state and focused row views**

Replace the disabled `Coming soon` block with the existing section-header pattern. Add:

- `@State private var submoduleEntries: [GitSubmoduleEntry] = []`
- `hasLoadedSubmodules`, `isLoadingSubmodules`, and one load error state.
- Header `+` present but disabled with help text `Available in Phase 2` only on this phase branch; remove that temporary disabled control when Phase 2 implements Add.
- Empty copy `No submodules`.
- Stable row selection and state badge.

Load only on first expansion and on matching `.repositoryDidChange` when already loaded.

- [ ] **Step 4: Wire open actions through MainWindowView**

Add closures:

```swift
onRequestOpenSubmodule: (URL) -> Void
onRequestShowSubmoduleInFinder: (URL) -> Void
onRequestOpenSubmoduleInTerminal: (URL) -> Void
```

Reuse `appState.newWindowRepoURL`, `openWindow(id: "main")`, `NSWorkspace.shared.selectFile`, and `/usr/bin/open -a Terminal`. Do not run these operations inside `GitStatusService`.

- [ ] **Step 5: Run focused tests and build**

```bash
rtk xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/SubmoduleSidebarPolicyTests -only-testing:macgitTests/SidebarViewStashTests
rtk xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```

Expected: tests pass and build ends with `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit the sidebar slice**

```bash
rtk git add macgit/Services/SidebarSettingsStore.swift macgit/Views/MainWindow/SidebarView.swift macgit/Views/MainWindow/SidebarSubmoduleViews.swift macgit/Views/MainWindow/MainWindowView.swift macgitTests/SubmoduleSidebarPolicyTests.swift macgitTests/SidebarViewStashTests.swift
rtk git commit -m "feat: show submodules in the sidebar"
```

## Task 4: Phase Verification and Roadmap Handoff

- [ ] Run the complete suite once:

```bash
rtk xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS'
```

- [ ] Run the macOS build:

```bash
rtk xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```

- [ ] After merge and verification on `main`, mark Phase 1 `[completed]` in the roadmap with the landed commit. Do not mark it completed while it exists only on the phase branch.
