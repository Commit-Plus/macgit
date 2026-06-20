o# Git Undo Phase 4 Local Branches Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add undo and redo for local branch create, local branch delete, and local branch checkout.

**Architecture:** Capture branch tips and current branch/ref before the original branch action. Undo create deletes the created branch only if its tip still matches the captured start point; undo delete recreates the branch at the captured tip; undo checkout returns to the previous ref.

**Tech Stack:** Swift 6, SwiftUI, XCTest, `xcodebuild`, `git branch`, `git checkout`, `git rev-parse`.

---

## Prerequisite

Complete and merge Phase 0 + 1A. Phase 2 is recommended because this phase uses expected-HEAD checking patterns, but it can define the same `expectedHeadMismatch` support if Phase 2 has not been implemented.

## Scope

This plan supports local branches only:

- Create branch from `BranchSheetView` and History create-branch sheet.
- Delete local branch from `BranchSheetView` and sidebar context menu.
- Checkout branch from sidebar/search.

Remote branch deletion and publishing are covered in Phase 7.

## File Structure

- Create `macgit/Services/GitBranchUndoSupport.swift`: current ref, branch tip, upstream capture, and safe delete checks.
- Modify `macgit/Services/GitUndoModels.swift`: add checkout/create/delete branch operations.
- Modify `macgit/Services/GitUndoExecutor.swift`: execute branch operations with expected-tip checks.
- Modify `macgit/Views/Common/BranchSheetView.swift`: accept undo manager and register create/delete undo.
- Modify `macgit/Views/MainWindow/SidebarView.swift`: accept undo manager and register sidebar delete undo.
- Modify `macgit/Views/MainWindow/MainWindowView.swift`: pass undo manager and register checkout undo.
- Modify `macgit/Views/History/HistoryView.swift`: accept undo manager for create branch from history.
- Create `macgitTests/GitBranchUndoSupportTests.swift`: helper tests.
- Create `macgitTests/GitUndoBranchIntegrationTests.swift`: real-repo branch undo tests.

## Task 1: Add Branch Undo Support

**Files:**

- Create: `macgit/Services/GitBranchUndoSupport.swift`
- Create: `macgitTests/GitBranchUndoSupportTests.swift`

- [ ] **Step 1: Write failing support tests**

Create `macgitTests/GitBranchUndoSupportTests.swift`:

```swift
import XCTest
@testable import macgit

final class GitBranchUndoSupportTests: XCTestCase {
    func testCurrentRefAndBranchTipAreResolved() async throws {
        let repoURL = try makeTempRepo()
        let support = GitBranchUndoSupport()

        let currentRef = try await support.currentRef(in: repoURL)
        let tip = try await support.tip(of: "main", in: repoURL)

        XCTAssertEqual(currentRef, "main")
        XCTAssertFalse(tip.isEmpty)
    }

    private func makeTempRepo() throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-branch-undo-support-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repoURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: repoURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repoURL)
        try "base\n".write(to: repoURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "initial"], in: repoURL)
        return repoURL
    }

    private func runGit(_ arguments: [String], in repositoryURL: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = arguments
        task.currentDirectoryURL = repositoryURL
        let stderr = Pipe()
        task.standardError = stderr
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let output = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "git failed"
            throw GitError.commandFailed(output)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitBranchUndoSupportTests
```

Expected: compilation fails with `cannot find 'GitBranchUndoSupport' in scope`.

- [ ] **Step 3: Create support helper**

Create `macgit/Services/GitBranchUndoSupport.swift`:

```swift
//
//  GitBranchUndoSupport.swift
//  macgit
//

import Foundation

struct GitBranchUndoSupport {
    private let runner: any GitCommandRunning

    init(runner: any GitCommandRunning = GitStatusService.shared) {
        self.runner = runner
    }

    func currentRef(in repositoryURL: URL) async throws -> String {
        let branch = try await runner.runGit(arguments: ["branch", "--show-current"], in: repositoryURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !branch.isEmpty { return branch }
        return try await runner.runGit(arguments: ["rev-parse", "--short", "HEAD"], in: repositoryURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func tip(of ref: String, in repositoryURL: URL) async throws -> String {
        try await runner.runGit(arguments: ["rev-parse", "\(ref)^{commit}"], in: repositoryURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func upstream(of branch: String, in repositoryURL: URL) async -> String? {
        try? await runner.runGit(arguments: ["rev-parse", "--abbrev-ref", "\(branch)@{upstream}"], in: repositoryURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 4: Run support tests**

Run:

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitBranchUndoSupportTests
```

Expected: tests pass.

- [ ] **Step 5: Commit**

Run:

```bash
git add macgit/Services/GitBranchUndoSupport.swift macgitTests/GitBranchUndoSupportTests.swift
git commit -m "feat: add local branch undo support"
```

Expected: commit succeeds.

## Task 2: Add Branch Operations to Undo Executor

**Files:**

- Modify: `macgit/Services/GitUndoModels.swift`
- Modify: `macgit/Services/GitUndoExecutor.swift`
- Create: `macgitTests/GitUndoBranchIntegrationTests.swift`

- [ ] **Step 1: Extend undo operations**

In `GitUndoOperation`, add:

```swift
case checkoutRef(ref: String)
case createLocalBranch(name: String, startPoint: String, checkout: Bool)
case deleteLocalBranch(name: String, force: Bool, expectedTip: String?)
case setUpstream(branch: String, upstream: String)
```

- [ ] **Step 2: Extend executor**

Add a branch support property to `GitUndoExecutor`:

```swift
private let branchSupport: GitBranchUndoSupport
```

Update initializer with:

```swift
branchSupport: GitBranchUndoSupport = GitBranchUndoSupport()
```

and assign it:

```swift
self.branchSupport = branchSupport
```

Add executor cases:

```swift
case .checkoutRef(let ref):
    _ = try await runner.runGit(arguments: ["checkout", ref], in: repositoryURL)
case .createLocalBranch(let name, let startPoint, let checkout):
    if checkout {
        _ = try await runner.runGit(arguments: ["checkout", "-b", name, startPoint], in: repositoryURL)
    } else {
        _ = try await runner.runGit(arguments: ["branch", name, startPoint], in: repositoryURL)
    }
case .deleteLocalBranch(let name, let force, let expectedTip):
    if let expectedTip {
        let actualTip = try await branchSupport.tip(of: name, in: repositoryURL)
        if actualTip != expectedTip {
            throw GitError.commandFailed("Cannot delete branch '\(name)' because its tip changed.")
        }
    }
    let flag = force ? "-D" : "-d"
    _ = try await runner.runGit(arguments: ["branch", flag, name], in: repositoryURL)
case .setUpstream(let branch, let upstream):
    _ = try await runner.runGit(arguments: ["branch", "--set-upstream-to", upstream, branch], in: repositoryURL)
```

- [ ] **Step 3: Write real-repo branch tests**

Create `macgitTests/GitUndoBranchIntegrationTests.swift`:

```swift
import XCTest
@testable import macgit

final class GitUndoBranchIntegrationTests: XCTestCase {
    func testUndoCreateBranchDeletesCreatedBranchWhenTipMatches() async throws {
        let repoURL = try makeTempRepo()
        let support = GitBranchUndoSupport()
        let start = try await support.tip(of: "main", in: repoURL)
        let executor = GitUndoExecutor()

        try await executor.execute(.createLocalBranch(name: "feature", startPoint: start, checkout: false), in: repoURL)
        XCTAssertTrue(await GitStatusService.shared.localBranches(in: repoURL).contains("feature"))

        try await executor.execute(.deleteLocalBranch(name: "feature", force: true, expectedTip: start), in: repoURL)
        XCTAssertFalse(await GitStatusService.shared.localBranches(in: repoURL).contains("feature"))
    }

    func testUndoDeleteBranchRecreatesBranchAtCapturedTip() async throws {
        let repoURL = try makeTempRepo()
        let support = GitBranchUndoSupport()
        let start = try await support.tip(of: "main", in: repoURL)
        let executor = GitUndoExecutor()
        try await executor.execute(.createLocalBranch(name: "feature", startPoint: start, checkout: false), in: repoURL)
        try await executor.execute(.deleteLocalBranch(name: "feature", force: true, expectedTip: start), in: repoURL)

        try await executor.execute(.createLocalBranch(name: "feature", startPoint: start, checkout: false), in: repoURL)

        XCTAssertEqual(try await support.tip(of: "feature", in: repoURL), start)
    }

    private func makeTempRepo() throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-undo-branch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repoURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: repoURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repoURL)
        try "base\n".write(to: repoURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "initial"], in: repoURL)
        return repoURL
    }

    private func runGit(_ arguments: [String], in repositoryURL: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = arguments
        task.currentDirectoryURL = repositoryURL
        let stderr = Pipe()
        task.standardError = stderr
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let output = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "git failed"
            throw GitError.commandFailed(output)
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitBranchUndoSupportTests -only-testing:macgitTests/GitUndoBranchIntegrationTests
```

Expected: tests pass.

- [ ] **Step 5: Commit**

Run:

```bash
git add macgit/Services/GitUndoModels.swift macgit/Services/GitUndoExecutor.swift macgitTests/GitUndoBranchIntegrationTests.swift
git commit -m "feat: execute local branch undo operations"
```

Expected: commit succeeds.

## Task 3: Register Branch Undo Entries in UI

**Files:**

- Modify: `macgit/Views/Common/BranchSheetView.swift`
- Modify: `macgit/Views/MainWindow/SidebarView.swift`
- Modify: `macgit/Views/MainWindow/MainWindowView.swift`
- Modify: `macgit/Views/History/HistoryView.swift`

- [ ] **Step 1: Add undo manager to branch-related views**

Add optional stored properties:

```swift
var undoManager: GitUndoManager? = nil
```

to:

- `BranchSheetView`
- `SidebarView`
- `HistoryView`

Pass `undoManager` from `MainWindowView` into each initializer where those views are created.

- [ ] **Step 2: Register create-branch undo in `BranchSheetView`**

In `createBranch()`, before creating the branch, add:

```swift
let support = GitBranchUndoSupport()
let startPoint = try await support.tip(of: commit ?? "HEAD", in: repositoryURL)
```

After successful create, add:

```swift
undoManager?.register(
    GitUndoEntry(
        repositoryURL: repositoryURL,
        label: "Create branch \(sanitizedName)",
        undoOperation: .deleteLocalBranch(name: sanitizedName, force: true, expectedTip: startPoint),
        redoOperation: .createLocalBranch(name: sanitizedName, startPoint: startPoint, checkout: checkoutNewBranch)
    )
)
```

- [ ] **Step 3: Register delete-branch undo in `BranchSheetView`**

Inside the local branch delete case, before `deleteBranch`, add:

```swift
let support = GitBranchUndoSupport()
let tip = try await support.tip(of: branch.name, in: repositoryURL)
let upstream = await support.upstream(of: branch.name, in: repositoryURL)
```

After successful delete, add:

```swift
var undoOperations: [GitUndoOperation] = [
    .createLocalBranch(name: branch.name, startPoint: tip, checkout: false)
]
if let upstream {
    undoOperations.append(.setUpstream(branch: branch.name, upstream: upstream))
}
undoManager?.register(
    GitUndoEntry(
        repositoryURL: repositoryURL,
        label: "Delete branch \(branch.name)",
        undoOperation: .sequence(undoOperations),
        redoOperation: .deleteLocalBranch(name: branch.name, force: forceDelete, expectedTip: tip)
    )
)
```

- [ ] **Step 4: Register checkout undo in `MainWindowView.performCheckout`**

Before checkout, add:

```swift
let support = GitBranchUndoSupport()
let previousRef = try await support.currentRef(in: repositoryURL)
```

After successful checkout, add:

```swift
undoManager.register(
    GitUndoEntry(
        repositoryURL: repositoryURL,
        label: "Checkout \(ref)",
        undoOperation: .checkoutRef(ref: previousRef),
        redoOperation: .checkoutRef(ref: ref)
    )
)
```

- [ ] **Step 5: Build and run tests**

Run:

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitBranchUndoSupportTests -only-testing:macgitTests/GitUndoBranchIntegrationTests
xcodebuild build -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS'
```

Expected: tests pass and app builds.

- [ ] **Step 6: Commit**

Run:

```bash
git add macgit/Views/Common/BranchSheetView.swift macgit/Views/MainWindow/SidebarView.swift macgit/Views/MainWindow/MainWindowView.swift macgit/Views/History/HistoryView.swift
git commit -m "feat: record undo entries for local branch actions"
```

Expected: commit succeeds.

## Self-Review

Spec coverage:

- Local branch create, delete, and checkout are covered.
- Remote branch actions are excluded and deferred to Phase 7.

Placeholder scan:

- Each action has concrete capture, undo, redo, and verification steps.

Type consistency:

- Branch operation enum cases match executor and UI registration snippets.
