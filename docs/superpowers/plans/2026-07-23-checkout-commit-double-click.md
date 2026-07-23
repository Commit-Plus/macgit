# Checkout Commit Double-Click Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Double-clicking a history commit opens the appropriate checkout flow: branch checkout for branch refs and detached-HEAD confirmation otherwise.

**Architecture:** `CommitRowView` emits a double-click callback. `HistoryView` resolves a checkout branch ref and owns detached-HEAD confirmation state, while `MainWindowView` receives branch checkout requests through its existing callback and sheet. Git execution remains in existing services.

**Tech Stack:** Swift, SwiftUI, XCTest, macOS `xcodebuild`.

## Global Constraints

- Do not launch the app; verification is complete when the prescribed build succeeds and focused tests pass.
- Every changed Swift file must retain the AGPL v3 header.
- Force checkout is used only when “Discard local changes” is selected.
- Successful checkout posts `.repositoryDidChange` with the repository URL.

---

### Task 1: Add testable checkout-ref selection policy

**Files:**
- Create: `macgit/Views/History/HistoryCheckoutPolicy.swift`
- Create: `macgitTests/HistoryCheckoutPolicyTests.swift`

**Interfaces:**
- Produces `HistoryCheckoutPolicy.branchRef(from:) -> String?`.
- A branch ref is a ref that is not `HEAD`, `HEAD -> ...`, or `tag: ...`; return the first such ref.

- [ ] **Step 1: Write failing tests** for local, remote, HEAD, and tag refs.
- [ ] **Step 2: Run `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/HistoryCheckoutPolicyTests test` and verify failure.**
- [ ] **Step 3: Implement the policy as a small pure enum/helper with the required AGPL header.**
- [ ] **Step 4: Re-run the focused test and verify it passes.**
- [ ] **Step 5: Commit `test: add history checkout ref policy`.**

### Task 2: Wire double-click and conditional detached checkout sheet

**Files:**
- Modify: `macgit/Views/History/CommitRowView.swift`
- Modify: `macgit/Views/History/HistoryView.swift`
- Modify: `macgit/Views/MainWindow/MainWindowView.swift`

**Interfaces:**
- `CommitRowView` accepts `onDoubleClick: () -> Void` and attaches it to a two-click tap gesture.
- `HistoryView` accepts `onRequestCheckout: (String, Bool) -> Void`, defaulting to a no-op for existing callers.

- [ ] **Step 1: Add the callback parameter and pass `onDoubleClick: { handleDoubleClick(for: commit) }` from the history row.**
- [ ] **Step 2: Add `hasUncommittedChanges` state and, on detached checkout, load `uncommittedChangeCount(in:)` before presenting the existing sheet.**
- [ ] **Step 3: Route a selected branch ref through `onRequestCheckout(ref, false)` and route other commits to the existing detached-HEAD confirmation.**
- [ ] **Step 4: Render “Discard local changes” only when `hasUncommittedChanges` is true, reset the flag after successful/cancelled presentation, and preserve the existing checkout error/change notification behavior.**
- [ ] **Step 5: Pass `MainWindowView`’s existing checkout callback into `HistoryView`.**
- [ ] **Step 6: Build with `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build` and verify success.**
- [ ] **Step 7: Commit `feat: checkout history commits by double click`.**

### Task 3: Final verification

**Files:**
- Test: `macgitTests/HistoryCheckoutPolicyTests.swift`

- [ ] **Step 1: Run the focused policy test once and record the result.**
- [ ] **Step 2: Run the prescribed macOS build once after all changes.**
- [ ] **Step 3: Inspect `git diff --check` and `git status --short`.**
