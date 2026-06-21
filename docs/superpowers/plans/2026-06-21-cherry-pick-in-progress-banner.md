# Cherry-Pick In-Progress Banner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a cherry-pick (or revert) fails with conflicts, detect the in-progress sequencer state and show a banner in the file-status view with **Continue** and **Abort** actions.

**Architecture:** Add a small `GitInProgressOperation` model and detection/continue/abort helpers to `GitStatusService`. Expose the current operation through `SyncState`. Render a banner at the top of `FileStatusView` that drives the new service methods and refreshes the repository state on completion.

**Tech Stack:** Swift, SwiftUI, XCTest, git via `Process()`.

---

## Background

`HistoryView.cherryPickCommit` runs `git cherry-pick <hash>` and shows the raw error on failure. Git does **not** roll back automatically on conflict — it leaves the repository in a *cherry-pick in progress* state with successfully-applied hunks already staged and conflict markers in the working tree. The file-status view correctly reflects this, but the app gives no indication that a sequencer operation is active or how to finish/abort it.

The same git machinery is used by `git revert`, so this plan handles both cherry-pick and revert in-progress states. Merge and rebase in-progress states are excluded from this plan to keep scope focused, but the model is designed to accommodate them later.

---

## File Structure

- **Create:**
  - `macgit/Models/GitInProgressOperation.swift` — enum representing an active sequencer operation.
- **Modify:**
  - `macgit/Services/GitStatusService+Diff.swift` — add detection, continue, and abort helpers for cherry-pick/revert.
  - `macgit/Services/SyncState.swift` — expose the current in-progress operation and refresh it.
  - `macgit/Views/FileStatus/FileStatusView.swift` — render the in-progress banner with Continue/Abort.
  - `macgit/Views/History/HistoryView.swift` — show the conflict banner instead of a raw error when cherry-pick fails due to conflicts.
- **Test:**
  - `macgitTests/GitInProgressOperationTests.swift` — integration tests for detection, continue, and abort using real temp repos.

---

## Task 1: Model the in-progress operation

**Files:**
- Create: `macgit/Models/GitInProgressOperation.swift`

- [ ] **Step 1.1: Add the enum and display helpers**

```swift
import Foundation

enum GitInProgressOperation: Equatable {
    case cherryPick(head: String)
    case revert(head: String)

    var displayName: String {
        switch self {
        case .cherryPick: return "Cherry-pick"
        case .revert: return "Revert"
        }
    }

    var shortHead: String {
        switch self {
        case .cherryPick(let head), .revert(let head):
            return String(head.prefix(7))
        }
    }

    var message: String {
        "\(displayName) in progress (\(shortHead)). Resolve conflicts, then continue or abort."
    }
}
```

- [ ] **Step 1.2: Build the project to confirm the new file compiles**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`
Expected: build succeeds.

---

## Task 2: Detect and control in-progress operations in GitStatusService

**Files:**
- Modify: `macgit/Services/GitStatusService+Diff.swift`

- [ ] **Step 2.1: Add detection helper**

After the existing `revertCommit` method, add:

```swift
func inProgressOperation(in repositoryURL: URL) async -> GitInProgressOperation? {
    if let head = try? await runGit(arguments: ["rev-parse", "--verify", "CHERRY_PICK_HEAD"], in: repositoryURL),
       !head.isEmpty {
        return .cherryPick(head: head.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    if let head = try? await runGit(arguments: ["rev-parse", "--verify", "REVERT_HEAD"], in: repositoryURL),
       !head.isEmpty {
        return .revert(head: head.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return nil
}
```

- [ ] **Step 2.2: Add continue/abort helpers**

Append to the same file:

```swift
func continueCherryPick(in repositoryURL: URL) async throws {
    _ = try await runGit(arguments: ["cherry-pick", "--continue"], in: repositoryURL)
}

func abortCherryPick(in repositoryURL: URL) async throws {
    _ = try await runGit(arguments: ["cherry-pick", "--abort"], in: repositoryURL)
}

func continueRevert(in repositoryURL: URL) async throws {
    _ = try await runGit(arguments: ["revert", "--continue"], in: repositoryURL)
}

func abortRevert(in repositoryURL: URL) async throws {
    _ = try await runGit(arguments: ["revert", "--abort"], in: repositoryURL)
}
```

- [ ] **Step 2.3: Build to verify**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`
Expected: build succeeds.

---

## Task 3: Expose the operation through SyncState

**Files:**
- Modify: `macgit/Services/SyncState.swift`

- [ ] **Step 3.1: Add published property**

After `activeSyncBranch`, add:

```swift
@Published var inProgressOperation: GitInProgressOperation? = nil
```

- [ ] **Step 3.2: Refresh the operation during refresh**

In `refresh(repositoryURL:)`, before the `MainActor.run` block, add:

```swift
let operation = await GitStatusService.shared.inProgressOperation(in: repositoryURL)
```

Inside the `MainActor.run` block, add:

```swift
self.inProgressOperation = operation
```

- [ ] **Step 3.3: Build to verify**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`
Expected: build succeeds.

---

## Task 4: Render the in-progress banner in FileStatusView

**Files:**
- Modify: `macgit/Views/FileStatus/FileStatusView.swift`

- [ ] **Step 4.1: Add banner view**

Near the top of `FileStatusView.body`, before the `NavigationSplitView`, add a conditional banner. The exact insertion point should be inside the `body` but outside the `NavigationSplitView`. Use the existing `@Environment` or pass `repositoryURL` through the view if needed.

Insert:

```swift
if let operation = syncState.inProgressOperation {
    VStack(spacing: 8) {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(operation.message)
                .font(.callout)
            Spacer()
        }

        HStack(spacing: 12) {
            Spacer()
            Button("Abort") {
                Task { await abortInProgressOperation(operation) }
            }
            .buttonStyle(.bordered)

            Button("Continue") {
                Task { await continueInProgressOperation(operation) }
            }
            .buttonStyle(.borderedProminent)
        }
    }
    .padding()
    .background(Color.orange.opacity(0.1))
    .cornerRadius(8)
    .padding([.horizontal, .top])
}
```

- [ ] **Step 4.2: Add continue/abort methods**

Add inside `FileStatusView`:

```swift
private func continueInProgressOperation(_ operation: GitInProgressOperation) async {
    guard let repositoryURL else { return }
    do {
        switch operation {
        case .cherryPick:
            try await GitStatusService.shared.continueCherryPick(in: repositoryURL)
        case .revert:
            try await GitStatusService.shared.continueRevert(in: repositoryURL)
        }
        await syncState.refresh(repositoryURL: repositoryURL)
        NotificationCenter.default.post(
            name: .repositoryDidChange,
            object: nil,
            userInfo: ["repositoryURL": repositoryURL]
        )
    } catch {
        await MainActor.run {
            syncState.showError(error.localizedDescription)
        }
    }
}

private func abortInProgressOperation(_ operation: GitInProgressOperation) async {
    guard let repositoryURL else { return }
    do {
        switch operation {
        case .cherryPick:
            try await GitStatusService.shared.abortCherryPick(in: repositoryURL)
        case .revert:
            try await GitStatusService.shared.abortRevert(in: repositoryURL)
        }
        await syncState.refresh(repositoryURL: repositoryURL)
        NotificationCenter.default.post(
            name: .repositoryDidChange,
            object: nil,
            userInfo: ["repositoryURL": repositoryURL]
        )
    } catch {
        await MainActor.run {
            syncState.showError(error.localizedDescription)
        }
    }
}
```

- [ ] **Step 4.3: Build to verify**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`
Expected: build succeeds.

---

## Task 5: Improve cherry-pick error handling in HistoryView

**Files:**
- Modify: `macgit/Views/History/HistoryView.swift`

- [ ] **Step 5.1: Detect conflict failures and show conflict banner**

In `cherryPickCommit`, replace the `catch` block:

```swift
catch {
    await MainActor.run {
        let message = error.localizedDescription
        if message.uppercased().contains("CONFLICT") {
            syncState.showConflict("Cherry-pick produced conflicts. Resolve them in the File status view, then continue or abort.")
        } else {
            errorMessage = message
            showingError = true
        }
    }
}
```

- [ ] **Step 5.2: Do the same for `revertCommit` if it exists**

If `HistoryView` has a revert action, apply the same conflict-handling pattern. If not, skip this step.

- [ ] **Step 5.3: Build to verify**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`
Expected: build succeeds.

---

## Task 6: Add integration tests

**Files:**
- Create: `macgitTests/GitInProgressOperationTests.swift`

- [ ] **Step 6.1: Test cherry-pick conflict detection and abort**

```swift
import XCTest
@testable import macgit

final class GitInProgressOperationTests: XCTestCase {
    private func makeTempRepo() async throws -> URL {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let service = GitStatusService.shared
        _ = try await service.runGit(arguments: ["init"], in: temp)
        _ = try await service.runGit(arguments: ["config", "user.email", "test@example.com"], in: temp)
        _ = try await service.runGit(arguments: ["config", "user.name", "Test"], in: temp)
        return temp
    }

    private func commit(file: String, content: String, message: String, in repo: URL) async throws {
        let path = repo.appendingPathComponent(file)
        try content.write(to: path, atomically: true, encoding: .utf8)
        _ = try await GitStatusService.shared.runGit(arguments: ["add", file], in: repo)
        _ = try await GitStatusService.shared.runGit(arguments: ["commit", "-m", message], in: repo)
    }

    func testCherryPickConflictLeavesInProgressState() async throws {
        let repo = try makeTempRepo()
        let service = GitStatusService.shared

        try await commit(file: "file.txt", content: "base\n", message: "base", in: repo)
        _ = try await service.runGit(arguments: ["checkout", "-b", "feature"], in: repo)
        try await commit(file: "file.txt", content: "feature\n", message: "feature", in: repo)
        _ = try await service.runGit(arguments: ["checkout", "main"], in: repo)
        try await commit(file: "file.txt", content: "main\n", message: "main", in: repo)

        let featureHead = try await service.runGit(arguments: ["rev-parse", "feature"], in: repo)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try await service.cherryPickCommit(featureHead, in: repo)
            XCTFail("cherry-pick should conflict")
        } catch {
            // expected
        }

        let operation = await service.inProgressOperation(in: repo)
        XCTAssertEqual(operation, .cherryPick(head: featureHead))

        try await service.abortCherryPick(in: repo)
        let afterAbort = await service.inProgressOperation(in: repo)
        XCTAssertNil(afterAbort)
    }
}
```

- [ ] **Step 6.2: Run the new test**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test -only-testing macgitTests/GitInProgressOperationTests`
Expected: test passes.

---

## Task 7: Verify everything

- [ ] **Step 7.1: Run the full test suite**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test`
Expected: all tests pass.

- [ ] **Step 7.2: Manual sanity check (describe only)**

Open a repo, create two branches that modify the same line, and cherry-pick one commit onto the other. Confirm:
- an error/conflict banner appears,
- the file-status view shows the in-progress banner with Continue/Abort,
- Abort returns the repo to a clean state,
- Continue (after resolving conflicts) completes the cherry-pick.

---

## Spec Coverage Self-Review

- Detect cherry-pick/revert in-progress state: **Task 2.1**
- Show banner in file-status view: **Task 4.1**
- Provide Continue/Abort actions: **Tasks 2.2 + 4.2**
- Replace raw error with conflict guidance on cherry-pick failure: **Task 5.1**
- Test with real temp repo: **Task 6.1**

No placeholders are used; each step contains exact file paths and code.
