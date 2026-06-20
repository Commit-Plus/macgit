# Worktree Phase 1: List, Display, Open Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user see all Git worktrees of a repo in a new `WORKTREES` sidebar section and open any worktree (or a Terminal at its path) from that section.

**Architecture:** Add a `WorktreeEntry` model and a `GitStatusService+Worktree` extension that parses `git worktree list --porcelain` and fetches per-worktree dirty counts in parallel. Add a `WORKTREES` section to `SidebarView` that renders entries (main / normal / locked / detached + dirty badge) and offers "Open" / "Open in Terminal" via closures wired through `MainWindowView` to the existing `AppState.newWindowRepoURL` window-spawn path.

**Tech Stack:** Swift 6, SwiftUI, XCTest, `xcodebuild`, `git worktree list --porcelain`, `git status --porcelain`.

**Design spec:** [docs/superpowers/specs/2026-06-20-worktree-management-design.md](../specs/2026-06-20-worktree-management-design.md)

---

## Prerequisite

None. This is the first phase of the Worktree roadmap ([2026-06-20-worktree-management-roadmap.md](2026-06-20-worktree-management-roadmap.md)).

## Scope

This phase supports:

- Listing worktrees (`git worktree list --porcelain`) with HEAD, branch, locked, and dirty count.
- Sidebar `WORKTREES` section rendering (main, normal, locked, detached, dirty badge).
- Opening a worktree in a new Commit+ window.
- Opening Terminal at a worktree's path.

This phase does NOT support create, remove, lock/unlock, prune, move/rename, checkout, or labels — those are Phases 2-4.

## File Structure

- Create `macgit/Services/WorktreeEntry.swift`: the worktree model.
- Create `macgit/Services/GitStatusService+Worktree.swift`: `worktrees(in:)` list primitive (porcelain parse + parallel dirty counts).
- Modify `macgit/Services/SidebarSettingsStore.swift`: add `worktreesExpanded` to `SidebarSectionState` and a `.worktrees` case in the toggle.
- Modify `macgit/Views/MainWindow/SidebarView.swift`: add `SidebarSection.worktrees`, the `WORKTREES` section UI, row rendering, and worktree loading.
- Modify `macgit/Views/MainWindow/MainWindowView.swift`: wire `onRequestOpenWorktree` and `onRequestOpenWorktreeInTerminal` closures into `SidebarView`.
- Create `macgitTests/WorktreeServiceTests.swift`: real-repo integration tests for listing and parsing.

## Task 1: Add WorktreeEntry Model and List Primitive

**Files:**
- Create: `macgit/Services/WorktreeEntry.swift`
- Create: `macgit/Services/GitStatusService+Worktree.swift`
- Create: `macgitTests/WorktreeServiceTests.swift`

- [ ] **Step 1: Write failing list/parse tests**

Create `macgitTests/WorktreeServiceTests.swift`:

```swift
import XCTest
@testable import macgit

final class WorktreeServiceTests: XCTestCase {
    func testListsOnlyMainWorktree() async throws {
        let repoURL = try makeTempRepo()
        let entries = await GitStatusService.shared.worktrees(in: repoURL)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].path, repoURL)
        XCTAssertFalse(entries[0].isLocked)
        XCTAssertNotNil(entries[0].branch)
        XCTAssertEqual(entries[0].dirtyCount, 0)
    }

    func testListsMultipleWorktreesAndParsesBranch() async throws {
        let repoURL = try makeTempRepo()
        let wtPath = repoURL.deletingLastPathComponent().appendingPathComponent("wt-\(UUID().uuidString)")
        try runGit(["worktree", "add", wtPath.path, "feature"], in: repoURL)

        let entries = await GitStatusService.shared.worktrees(in: repoURL)

        XCTAssertEqual(entries.count, 2)
        let main = entries.first(where: { $0.path == repoURL })
        let linked = entries.first(where: { $0.path == wtPath })
        XCTAssertNotNil(main)
        XCTAssertEqual(linked?.branch, "feature")
        XCTAssertFalse(linked?.isLocked ?? true)
    }

    func testParsesLockedWorktree() async throws {
        let repoURL = try makeTempRepo()
        let wtPath = repoURL.deletingLastPathComponent().appendingPathComponent("wt-\(UUID().uuidString)")
        try runGit(["worktree", "add", wtPath.path, "feature"], in: repoURL)
        try runGit(["worktree", "lock", wtPath.path], in: repoURL)

        let entries = await GitStatusService.shared.worktrees(in: repoURL)
        let linked = entries.first(where: { $0.path == wtPath })
        XCTAssertEqual(linked?.isLocked, true)
    }

    func testParsesDetachedHeadWorktree() async throws {
        let repoURL = try makeTempRepo()
        let wtPath = repoURL.deletingLastPathComponent().appendingPathComponent("wt-\(UUID().uuidString)")
        // Detached HEAD at current commit
        let head = try runGitCapture(["rev-parse", "HEAD"], in: repoURL)
        try runGit(["worktree", "add", "--detach", wtPath.path, head], in: repoURL)

        let entries = await GitStatusService.shared.worktrees(in: repoURL)
        let linked = entries.first(where: { $0.path == wtPath })
        XCTAssertNil(linked?.branch)
        XCTAssertFalse(linked?.head.isEmpty ?? true)
    }

    func testDirtyCountReflectsWorktreeStatus() async throws {
        let repoURL = try makeTempRepo()
        let wtPath = repoURL.deletingLastPathComponent().appendingPathComponent("wt-\(UUID().uuidString)")
        try runGit(["worktree", "add", wtPath.path, "feature"], in: repoURL)
        // Make the worktree dirty
        try "dirty\n".write(to: wtPath.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)

        let entries = await GitStatusService.shared.worktrees(in: repoURL)
        let linked = entries.first(where: { $0.path == wtPath })
        XCTAssertEqual(linked?.dirtyCount, 1)
    }

    // MARK: - Helpers

    private func makeTempRepo() throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-worktree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repoURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: repoURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repoURL)
        try "base\n".write(to: repoURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "initial"], in: repoURL)
        // Create a feature branch for worktree add tests
        try runGit(["branch", "feature"], in: repoURL)
        return repoURL
    }

    private func runGit(_ arguments: [String], in repositoryURL: URL) throws {
        _ = try runGitCapture(arguments, in: repositoryURL)
    }

    private func runGitCapture(_ arguments: [String], in repositoryURL: URL) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = arguments
        task.currentDirectoryURL = repositoryURL
        let pipe = Pipe()
        task.standardOutput = pipe
        let stderr = Pipe()
        task.standardError = stderr
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let output = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "git failed"
            throw GitError.commandFailed(output)
        }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/WorktreeServiceTests
```

Expected: build fails with `cannot find 'worktrees(in:)'` and `cannot find 'WorktreeEntry'`.

- [ ] **Step 3: Create WorktreeEntry model**

Create `macgit/Services/WorktreeEntry.swift`:

```swift
//
//  WorktreeEntry.swift
//  macgit
//

import Foundation

struct WorktreeEntry: Identifiable, Equatable {
    let id = UUID()
    let path: URL
    let head: String          // short sha
    let branch: String?       // nil when detached
    let isLocked: Bool
    let dirtyCount: Int       // -1 if status could not be read
    var label: String?        // merged from WorktreeLabelStore in Phase 2; nil here

    var displayTitle: String {
        if let label, !label.isEmpty { return label }
        if let branch { return branch }
        return "detached \(head)"
    }
}
```

Note: `isMain` is NOT a stored/computed property on the model — it is computed in the view by comparing `entry.path == repositoryURL` (see Task 3 Step 4). This keeps the model sidecar-free and avoids a tautological self-comparison. Add the new file to the `macgit` target in Xcode (it is auto-included if it lives under `macgit/Services/` and the target uses a folder-based membership; otherwise add it via the `project.pbxproj`). If the build in Step 5 fails to find the type, open `macgit.xcodeproj` and add the file to the `macgit` target.

- [ ] **Step 4: Create the worktree list primitive**

Create `macgit/Services/GitStatusService+Worktree.swift`:

```swift
//
//  GitStatusService+Worktree.swift
//  macgit
//

import Foundation

extension GitStatusService {
    /// List all worktrees of `repositoryURL`, with per-worktree dirty counts fetched in parallel.
    func worktrees(in repositoryURL: URL) async -> [WorktreeEntry] {
        let output = (try? await runGit(arguments: ["worktree", "list", "--porcelain"], in: repositoryURL)) ?? ""
        let parsed = parseWorktreePorcelain(output)

        // Fetch dirty counts in parallel (pattern from loadBranches sync status).
        var counts: [URL: Int] = [:]
        await withTaskGroup(of: (URL, Int).self) { group in
            for entry in parsed {
                let path = entry.path
                group.addTask {
                    let count = await self.dirtyCount(in: path)
                    return (path, count)
                }
            }
            for await (path, count) in group {
                counts[path] = count
            }
        }

        return parsed.map { entry in
            WorktreeEntry(
                path: entry.path,
                head: entry.head,
                branch: entry.branch,
                isLocked: entry.isLocked,
                dirtyCount: counts[entry.path] ?? -1,
                label: nil
            )
        }
    }

    /// Number of modified/untracked files in `worktreePath`, or -1 if `git status` fails.
    func dirtyCount(in worktreePath: URL) async -> Int {
        guard let output = try? await runGit(arguments: ["status", "--porcelain"], in: worktreePath) else {
            return -1
        }
        return output.split(separator: "\n").filter { !$0.isEmpty }.count
    }

    // MARK: - Porcelain parsing

    private struct ParsedWorktree {
        let path: URL
        let head: String
        let branch: String?
        let isLocked: Bool
    }

    private func parseWorktreePorcelain(_ output: String) -> [ParsedWorktree] {
        var entries: [ParsedWorktree] = []
        var path: URL?
        var head: String = ""
        var branch: String?
        var isLocked = false

        func flush() {
            guard let path else { return }
            entries.append(ParsedWorktree(path: path, head: head, branch: branch, isLocked: isLocked))
            path = nil
            head = ""
            branch = nil
            isLocked = false
        }

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.isEmpty {
                flush()
                continue
            }
            if line.hasPrefix("worktree ") {
                flush()
                let pathString = String(line.dropFirst("worktree ".count))
                path = URL(fileURLWithPath: pathString)
            } else if line.hasPrefix("HEAD ") {
                head = String(line.dropFirst("HEAD ".count))
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                // refs/heads/<name> -> <name>
                branch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
            } else if line == "locked" {
                isLocked = true
            }
            // Ignore "bare", "detached", "reason <text>", etc.
        }
        flush()
        return entries
    }
}
```

- [ ] **Step 5: Run list/parse tests**

Run:

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/WorktreeServiceTests
```

Expected: all five tests pass. If the build cannot find `WorktreeEntry` or `GitStatusService+Worktree`, add the two new files to the `macgit` target in Xcode and re-run.

- [ ] **Step 6: Commit**

Run:

```bash
git add macgit/Services/WorktreeEntry.swift macgit/Services/GitStatusService+Worktree.swift macgitTests/WorktreeServiceTests.swift
git commit -m "feat: add worktree list primitive with porcelain parsing"
```

Expected: commit succeeds.

## Task 2: Add Worktrees Section State to Sidebar Settings

**Files:**
- Modify: `macgit/Services/SidebarSettingsStore.swift`
- Modify: `macgitTests/SidebarViewStashTests.swift` (add a parallel decode test) — optional but recommended

- [ ] **Step 1: Write failing section-state decode test**

Add this test to `macgitTests/SidebarViewStashTests.swift` (or a new `macgitTests/SidebarSectionStateTests.swift` if you prefer to keep it separate):

```swift
func testSidebarSectionStateDecodesMissingWorktreesExpandedAsTrue() throws {
    let json = """
    {"branchesExpanded": true, "tagsExpanded": false}
    """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(SidebarSectionState.self, from: json)
    XCTAssertTrue(decoded.worktreesExpanded)
}
```

If creating a new file `macgitTests/SidebarSectionStateTests.swift` instead, use:

```swift
import XCTest
@testable import macgit

final class SidebarSectionStateTests: XCTestCase {
    func testSidebarSectionStateDecodesMissingWorktreesExpandedAsTrue() throws {
        let json = """
        {"branchesExpanded": true, "tagsExpanded": false}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SidebarSectionState.self, from: json)
        XCTAssertTrue(decoded.worktreesExpanded)
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/SidebarSectionStateTests
```

Expected: fails with `cannot find 'worktreesExpanded'`.

- [ ] **Step 3: Add worktreesExpanded to SidebarSectionState**

In `macgit/Services/SidebarSettingsStore.swift`, add `worktreesExpanded` to the `SidebarSectionState` struct:

```swift
struct SidebarSectionState: Codable {
    var branchesExpanded: Bool = true
    var tagsExpanded: Bool = true
    var remotesExpanded: Bool = true
    var stashesExpanded: Bool = true
    var worktreesExpanded: Bool = true

    init(
        branchesExpanded: Bool = true,
        tagsExpanded: Bool = true,
        remotesExpanded: Bool = true,
        stashesExpanded: Bool = true,
        worktreesExpanded: Bool = true
    ) {
        self.branchesExpanded = branchesExpanded
        self.tagsExpanded = tagsExpanded
        self.remotesExpanded = remotesExpanded
        self.stashesExpanded = stashesExpanded
        self.worktreesExpanded = worktreesExpanded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        branchesExpanded = try container.decodeIfPresent(Bool.self, forKey: .branchesExpanded) ?? true
        tagsExpanded = try container.decodeIfPresent(Bool.self, forKey: .tagsExpanded) ?? true
        remotesExpanded = try container.decodeIfPresent(Bool.self, forKey: .remotesExpanded) ?? true
        stashesExpanded = try container.decodeIfPresent(Bool.self, forKey: .stashesExpanded) ?? true
        worktreesExpanded = try container.decodeIfPresent(Bool.self, forKey: .worktreesExpanded) ?? true
    }
}
```

`Codable` auto-synthesizes `CodingKeys` for the added property, so no manual key enum is needed.

- [ ] **Step 4: Add `.worktrees` case to the toggle**

In `SidebarSettingsStore.toggleSection(_:for:)`, add a case before `default`:

```swift
case .worktrees:
    state.worktreesExpanded.toggle()
```

- [ ] **Step 5: Run test to verify pass**

Run:

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/SidebarSectionStateTests
```

Expected: test passes.

- [ ] **Step 6: Commit**

Run:

```bash
git add macgit/Services/SidebarSettingsStore.swift macgitTests/SidebarSectionStateTests.swift
git commit -m "feat: persist worktrees sidebar section expand state"
```

Expected: commit succeeds.

## Task 3: Add SidebarSection.worktrees and WORKTREES Section UI

**Files:**
- Modify: `macgit/Views/MainWindow/SidebarView.swift`

This task is UI-only and is verified by building and manual run (per spec, UI rendering is not unit-tested). It adds the section, row rendering, and data loading. Action wiring (open / open in terminal) is added in Task 4.

- [ ] **Step 1: Add the `.worktrees` section enum case**

In `macgit/Views/MainWindow/SidebarView.swift`, add to `SidebarSection`:

```swift
enum SidebarSection: String, CaseIterable {
    case workspace = "WORKSPACE"
    case branches = "BRANCHES"
    case worktrees = "WORKTREES"
    case tags = "TAGS"
    case remotes = "REMOTES"
    case stashes = "STASHES"
    case submodules = "SUBMODULES"
    case subtrees = "SUBTREES"

    var items: [SidebarItem] {
        switch self {
        case .workspace:
            return [.fileStatus, .history, .search]
        default:
            return []
        }
    }
}
```

Add a `SidebarSelection` case for worktrees:

```swift
enum SidebarSelection: Hashable {
    case item(SidebarItem)
    case branch(String)
    case tag(String)
    case remoteBranch(String)
    case stash(String)
    case worktree(URL)
    case head(String)
}
```

- [ ] **Step 2: Add state and closures to SidebarView**

Add stored state and closures near the existing `stashEntries` state and the init parameters:

```swift
@State private var worktreeEntries: [WorktreeEntry] = []
@State private var isLoadingWorktrees = false
```

Add closure properties and init parameters (after `onRequestDeleteStash`):

```swift
let onRequestOpenWorktree: (URL) -> Void
let onRequestOpenWorktreeInTerminal: (URL) -> Void
```

Update the memberwise init signature to include them (with defaults for the preview):

```swift
init(
    repositoryURL: URL,
    selection: Binding<SidebarSelection?>,
    isBranchSyncing: @escaping (String) -> Bool = { _ in false },
    onRequestCheckout: @escaping (String, Bool) -> Void,
    onRequestFetchBranch: @escaping (String) -> Void,
    onRequestApplyStash: @escaping (String) -> Void = { _ in },
    onRequestDeleteStash: @escaping (String) -> Void = { _ in },
    onRequestOpenWorktree: @escaping (URL) -> Void = { _ in },
    onRequestOpenWorktreeInTerminal: @escaping (URL) -> Void = { _ in },
    onRequestSearch: @escaping () -> Void = {}
) {
    self.repositoryURL = repositoryURL
    self._selection = selection
    self.isBranchSyncing = isBranchSyncing
    self.onRequestCheckout = onRequestCheckout
    self.onRequestFetchBranch = onRequestFetchBranch
    self.onRequestApplyStash = onRequestApplyStash
    self.onRequestDeleteStash = onRequestDeleteStash
    self.onRequestOpenWorktree = onRequestOpenWorktree
    self.onRequestOpenWorktreeInTerminal = onRequestOpenWorktreeInTerminal
    self.onRequestSearch = onRequestSearch
}
```

- [ ] **Step 3: Add the WORKTREES section to the List**

Insert this section between the `BRANCHES` section and the `TAGS` section in the `body`:

```swift
// WORKTREES section
Section {
    if sectionStates.worktreesExpanded {
        if isLoadingWorktrees && worktreeEntries.isEmpty {
            ProgressView()
                .scaleEffect(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
        } else if worktreeEntries.isEmpty {
            Text("No worktrees")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(worktreeEntries) { entry in
                worktreeRowView(for: entry)
            }
        }
    }
} header: {
    sectionHeader(SidebarSection.worktrees, isExpanded: sectionStates.worktreesExpanded)
}
```

- [ ] **Step 4: Add the worktree row view**

Add this method to `SidebarView` (near `stashRowView`):

```swift
@ViewBuilder
private func worktreeRowView(for entry: WorktreeEntry) -> some View {
    let isMain = entry.path == repositoryURL
    let baseView = HStack(spacing: 4) {
        Image(systemName: entry.isLocked ? "lock.fill"
              : (isMain ? "circle.fill" : "folder"))
            .font(.system(size: isMain ? 7 : 10))
            .foregroundStyle(isMain ? Color.accentColor : .secondary)
            .frame(width: 16, alignment: .center)

        Text(entry.displayTitle)
            .font(.system(size: 12))
            .fontWeight(isMain ? .bold : .regular)
            .italic(isMain)
            .lineLimit(1)

        if isMain {
            Text("(this)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }

        Spacer()

        if !isMain, entry.dirtyCount > 0 {
            Text("\(entry.dirtyCount)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.orange)
                .cornerRadius(4)
        } else if !isMain, entry.dirtyCount < 0 {
            Text("?")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
    .padding(.vertical, 2)
    .contentShape(Rectangle())

    baseView
        .tag(SidebarSelection.worktree(entry.path))
        .onTapGesture {
            selection = .worktree(entry.path)
        }
        .onTapGesture(count: 2) {
            onRequestOpenWorktree(entry.path)
        }
        .contextMenu {
            worktreeContextMenu(for: entry, isMain: isMain)
        }
}
```

- [ ] **Step 5: Add the worktree context menu**

Add this method to `SidebarView` (near `branchContextMenu`):

```swift
@ViewBuilder
private func worktreeContextMenu(for entry: WorktreeEntry, isMain: Bool) -> some View {
    Button("Open in New Window") {
        onRequestOpenWorktree(entry.path)
    }

    Button("Open in Terminal") {
        onRequestOpenWorktreeInTerminal(entry.path)
    }

    Divider()

    Button("Copy Path to Clipboard") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.path.path, forType: .string)
    }

    // Create / Remove / Set Label / Lock / Rename / Switch Branch are added in Phases 2-4.
}
```

- [ ] **Step 6: Add worktree loading**

Add this method to `SidebarView` (near `loadStashes`):

```swift
private func loadWorktrees() async {
    isLoadingWorktrees = true
    defer { isLoadingWorktrees = false }
    let entries = await GitStatusService.shared.worktrees(in: repositoryURL)
    await MainActor.run {
        worktreeEntries = entries
    }
}
```

Update the `.task` and `.onReceive(.repositoryDidChange)` blocks to also call `await loadWorktrees()` (add it next to the existing `loadBranches` / `loadTags` / `loadRemotes` / `loadStashes` calls):

```swift
.task {
    loadSectionStates()
    await loadBranches()
    await loadWorktrees()
    await loadTags()
    await loadRemotes()
    await loadStashes()
}
.onReceive(NotificationCenter.default.publisher(for: .repositoryDidChange)) { _ in
    Task {
        await loadBranches()
        await loadWorktrees()
        await loadTags()
        await loadRemotes()
        await loadStashes()
    }
}
```

- [ ] **Step 7: Build and manually verify**

Run:

```bash
xcodebuild build -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS'
```

Expected: build succeeds. Then launch the app on a repo that has worktrees (e.g. this very repo, which has several under `.worktrees/`):

```bash
open $(ls -dt ~/Library/Developer/Xcode/DerivedData/macgit-*/Build/Products/Debug/Commit+.app | head -n 1)
```

Expected: a `WORKTREES` section appears in the sidebar between `BRANCHES` and `TAGS`, listing the main worktree (bold, italic, `(this)`) plus each linked worktree. Clicking a row selects it; double-clicking does nothing yet (open wiring is Task 4). The header collapses/expands and persists across restarts.

- [ ] **Step 8: Commit**

Run:

```bash
git add macgit/Views/MainWindow/SidebarView.swift
git commit -m "feat: render worktrees section in sidebar"
```

Expected: commit succeeds.

## Task 4: Wire Open Worktree and Open in Terminal

**Files:**
- Modify: `macgit/Views/MainWindow/MainWindowView.swift`

- [ ] **Step 1: Add openWindow and appState to MainWindowView**

In `macgit/Views/MainWindow/MainWindowView.swift`, add these environment properties near the top of `MainWindowView` (next to the existing `@State` declarations):

```swift
@EnvironmentObject private var appState: AppState
@Environment(\.openWindow) private var openWindow
```

`ContentView` already injects `AppState` as an environment object, so `MainWindowView` (which is rendered inside `ContentView`) can read it.

- [ ] **Step 2: Add helper methods to MainWindowView**

Add these methods near the existing `openTerminal()` helper:

```swift
private func openWorktreeInNewWindow(at path: URL) {
    appState.newWindowRepoURL = path
    openWindow(id: "main")
}

private func openWorktreeInTerminal(at path: URL) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-a", "Terminal", path.path]
    do {
        try process.run()
    } catch {
        print("Failed to open Terminal for worktree: \(error)")
    }
}
```

- [ ] **Step 3: Pass the closures into SidebarView**

In `sidebarPane`, extend the `SidebarView(...)` call with the two new closures (after `onRequestDeleteStash`):

```swift
onRequestOpenWorktree: { path in
    openWorktreeInNewWindow(at: path)
},
onRequestOpenWorktreeInTerminal: { path in
    openWorktreeInTerminal(at: path)
},
```

- [ ] **Step 4: Build and manually verify**

Run:

```bash
xcodebuild build -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS'
```

Expected: build succeeds. Launch the app on this repo. Double-click a non-main worktree row in the `WORKTREES` section: a new Commit+ window opens scoped to that worktree path (the sidebar of the new window shows that worktree's branches). Right-click a worktree row and choose "Open in Terminal": a Terminal window opens at that path.

- [ ] **Step 5: Commit**

Run:

```bash
git add macgit/Views/MainWindow/MainWindowView.swift
git commit -m "feat: open worktree in new window or terminal"
```

Expected: commit succeeds.

## Task 5: Update the SidebarView Preview

**Files:**
- Modify: `macgit/Views/MainWindow/SidebarView.swift`

- [ ] **Step 1: Update the Preview to compile**

The `#Preview` at the bottom of `SidebarView.swift` calls `SidebarView(...)` and must now provide the two new closures (they have defaults, but the existing preview already passes several closures explicitly, so add the new ones for clarity). Update the preview to:

```swift
#Preview {
    SidebarView(
        repositoryURL: URL(fileURLWithPath: "/tmp"),
        selection: .constant(nil),
        isBranchSyncing: { _ in false },
        onRequestCheckout: { _, _ in },
        onRequestFetchBranch: { _ in },
        onRequestOpenWorktree: { _ in },
        onRequestOpenWorktreeInTerminal: { _ in }
    )
}
```

- [ ] **Step 2: Build to verify**

Run:

```bash
xcodebuild build -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS'
```

Expected: build succeeds with no preview-related warnings.

- [ ] **Step 3: Commit**

Run:

```bash
git add macgit/Views/MainWindow/SidebarView.swift
git commit -m "chore: update SidebarView preview for worktree closures"
```

Expected: commit succeeds.

## Task 6: Final Verification and Roadmap Status Update

- [ ] **Step 1: Run the full test suite**

Run:

```bash
xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS'
```

Expected: all tests pass, including the new `WorktreeServiceTests` and `SidebarSectionStateTests`, and no existing tests regress.

- [ ] **Step 2: Build the app and smoke-test**

Run:

```bash
xcodebuild build -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS'
open $(ls -dt ~/Library/Developer/Xcode/DerivedData/macgit-*/Build/Products/Debug/Commit+.app | head -n 1)
```

Manual checks:
- `WORKTREES` section visible between `BRANCHES` and `TAGS`.
- Main worktree rendered bold/italic with `(this)`.
- A locked worktree (if present, e.g. lock one via CLI first) shows the lock icon.
- A detached worktree (if present) shows `detached <sha>`.
- A dirty worktree shows an orange dirty count badge; a clean one shows no badge.
- Double-click opens a new window scoped to the worktree.
- "Open in Terminal" opens Terminal at the worktree path.
- Section collapse/expand persists across app relaunch.

- [ ] **Step 3: Mark Phase 1 complete in the roadmap**

In `docs/superpowers/plans/2026-06-20-worktree-management-roadmap.md`, update the Plan Index line for Phase 1 from `[pending]` to `[completed]` and include the branch/worktree it landed on, e.g.:

```
- Phase 1: [completed] 2026-06-20-worktree-phase-1-list-open.md (branch: codex/worktree-phase-1)
```

- [ ] **Step 4: Commit roadmap status**

Run:

```bash
git add docs/superpowers/plans/2026-06-20-worktree-management-roadmap.md
git commit -m "docs: mark worktree phase 1 complete"
```

Expected: commit succeeds.

## Self-Review

Spec coverage:

- List (scope #1) — Task 1 implements `worktrees(in:)` and Task 3 renders the section.
- Open (scope #3) — Task 4 wires open-in-new-window.
- Open in Terminal (AI agent choice D) — Task 4 wires open-in-terminal.
- Main/locked/detached/dirty rendering — Tasks 1 and 3 cover parsing and rendering.
- Create / Remove / Switch / Prune / Lock / Unlock / Rename / Label — explicitly out of scope for Phase 1 (Phases 2-4).

Placeholder scan:

- Every task has concrete file paths, code snippets, commands, and expected outcomes. UI tasks (Task 3 and Task 4) are verified by build + manual run per the spec's "Không test UI rendering" rule.

Type consistency:

- `WorktreeEntry` fields (`path`, `head`, `branch`, `isLocked`, `dirtyCount`, `label`) match the spec and are used consistently in the service and the row view.
- `SidebarSelection.worktree(URL)` matches the `onRequestOpenWorktree: (URL) -> Void` closure signature.
- `SidebarSection.worktrees` matches the `case .worktrees:` added to `SidebarSettingsStore.toggleSection`.
- `worktreesExpanded` is added to both the struct and the decoder and used in the section header binding.
