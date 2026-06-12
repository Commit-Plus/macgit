# Tags Sidebar Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a TAGS section to the sidebar that lists all Git tags, allows single-click navigation to the tag's commit in history, and double-click checkout with a detached HEAD confirmation.

**Architecture:** Extend the existing `SidebarSelection` enum with a `.tag(String)` case. Reuse the branch tree builder for hierarchical tag grouping. Wire tag selection through `MainWindowView` to `HistoryView` the same way branches work. Add a new alert for detached HEAD confirmation on tag double-click.

**Tech Stack:** Swift, SwiftUI, Git command-line via `GitStatusService`

---

## File Map

| File | Responsibility |
|------|---------------|
| `macgit/Services/GitStatusService+Branch.swift` | Add `tags()` and `tagCommitHash()` methods |
| `macgit/Views/MainWindow/SidebarView.swift` | Add `.tag` case, render TAGS section, handle click gestures |
| `macgit/Views/MainWindow/MainWindowView.swift` | Handle `.tag` selection, pass to HistoryView, add detached HEAD alert |

---

### Task 1: Add tag methods to GitStatusService

**Files:**
- Modify: `macgit/Services/GitStatusService+Branch.swift`

- [ ] **Step 1: Add `tags(in:)` method**

Append to `macgit/Services/GitStatusService+Branch.swift` (after line 55):

```swift
    func tags(in repositoryURL: URL) async -> [String] {
        let output = (try? await runGit(arguments: ["tag", "--list"], in: repositoryURL)) ?? ""
        return output.split(separator: "\n").map { String($0) }.filter { !$0.isEmpty }
    }

    func tagCommitHash(tag: String, in repositoryURL: URL) async -> String? {
        let output = (try? await runGit(arguments: ["rev-parse", tag], in: repositoryURL))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output?.isEmpty == false ? output : nil
    }
```

- [ ] **Step 2: Verify no syntax errors**

Build: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`
Expected: Clean build (no new errors from these additions)

- [ ] **Step 3: Commit**

```bash
git add macgit/Services/GitStatusService+Branch.swift
git commit -m "feat: add tag list and tag hash resolution to GitStatusService"
```

---

### Task 2: Extend SidebarSelection and add tag state to SidebarView

**Files:**
- Modify: `macgit/Views/MainWindow/SidebarView.swift`

- [ ] **Step 1: Add `.tag` case to `SidebarSelection`**

Change `macgit/Views/MainWindow/SidebarView.swift` line 10-13:

```swift
enum SidebarSelection: Hashable {
    case item(SidebarItem)
    case branch(String)
    case tag(String)
}
```

- [ ] **Step 2: Add tag state variables**

After line 74 (`@State private var isLoadingBranches = false`), add:

```swift
    @State private var tagNodes: [BranchNode] = []
    @State private var isLoadingTags = false
    @State private var expandedTagFolders: Set<String> = []
```

- [ ] **Step 3: Add tag loading method**

After `loadBranches()` (line 324), add:

```swift
    private func loadTags() async {
        isLoadingTags = true
        defer { isLoadingTags = false }
        let tags = await GitStatusService.shared.tags(in: repositoryURL)
        let tree = buildBranchTree(from: tags)
        let allFolders = collectFolderPaths(from: tree)
        await MainActor.run {
            tagNodes = tree
            if expandedTagFolders.isEmpty {
                expandedTagFolders = allFolders
            }
        }
    }
```

- [ ] **Step 4: Add tag row view helper**

After `branchRowView(for:)` (line 226), add:

```swift
    @ViewBuilder
    private func tagRowView(for row: BranchRowItem) -> some View {
        let baseView = HStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(0..<row.indent, id: \.self) { _ in
                    Color.clear
                        .frame(width: 16)
                }
            }

            if row.isFolder {
                Image(systemName: expandedTagFolders.contains(row.fullPath) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .center)
            } else {
                Image(systemName: "tag")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .center)
            }

            Text(row.name)
                .font(.system(size: 12))
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())

        if row.isFolder {
            baseView
                .onTapGesture {
                    if expandedTagFolders.contains(row.fullPath) {
                        expandedTagFolders.remove(row.fullPath)
                    } else {
                        expandedTagFolders.insert(row.fullPath)
                    }
                }
        } else {
            baseView
                .tag(SidebarSelection.tag(row.fullPath))
                .onTapGesture {
                    selection = .tag(row.fullPath)
                }
                .onTapGesture(count: 2) {
                    onRequestCheckout(row.fullPath)
                }
                .contextMenu {
                    Button("Copy Tag Name to Clipboard") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(row.fullPath, forType: .string)
                    }
                }
        }
    }
```

- [ ] **Step 5: Add visible tag rows computed property**

After `visibleBranchRows` (line 164), add:

```swift
    private var visibleTagRows: [BranchRowItem] {
        var rows: [BranchRowItem] = []
        func traverse(_ nodes: [BranchNode], indent: Int) {
            for node in nodes {
                rows.append(BranchRowItem(
                    id: node.id,
                    name: node.name,
                    fullPath: node.fullPath,
                    isFolder: node.isFolder,
                    indent: indent
                ))
                if node.isFolder && expandedTagFolders.contains(node.fullPath) {
                    traverse(node.children, indent: indent + 1)
                }
            }
        }
        traverse(tagNodes, indent: 0)
        return rows
    }
```

- [ ] **Step 6: Replace TAGS placeholder section with real content**

Replace lines 110-118:

```swift
            // TAGS section
            Section(SidebarSection.tags.rawValue) {
                if isLoadingTags && tagNodes.isEmpty {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                } else if tagNodes.isEmpty {
                    Text("No tags")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleTagRows) { row in
                        tagRowView(for: row)
                    }
                }
            }

            // Other placeholder sections
            ForEach(SidebarSection.allCases.dropFirst(3), id: \.self) { section in
                Section(section.rawValue) {
                    Text("Coming soon")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(true)
            }
```

- [ ] **Step 7: Add tag loading to task and notification handler**

Change `.task` block (line 121-123):

```swift
        .task {
            await loadBranches()
            await loadTags()
        }
```

Change `.onReceive` block (line 124-126):

```swift
        .onReceive(NotificationCenter.default.publisher(for: .repositoryDidChange)) { _ in
            Task {
                await loadBranches()
                await loadTags()
            }
        }
```

- [ ] **Step 8: Verify build**

Build: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`
Expected: Clean build

- [ ] **Step 9: Commit**

```bash
git add macgit/Views/MainWindow/SidebarView.swift
git commit -m "feat: add TAGS section to sidebar with click handling"
```

---

### Task 3: Wire tag selection through MainWindowView

**Files:**
- Modify: `macgit/Views/MainWindow/MainWindowView.swift`

- [ ] **Step 1: Add selected tag name state**

After line 31 (`@State private var selectedBranchName: String? = nil`), add:

```swift
    @State private var selectedTagName: String? = nil
```

- [ ] **Step 2: Update detail view switch to handle tags**

Change lines 54-65:

```swift
                Group {
                    switch selectedItem {
                    case .item(.fileStatus):
                        FileStatusView(repositoryURL: repositoryURL, syncState: syncState)
                    case .item(.history), .branch:
                        HistoryView(repositoryURL: repositoryURL, selectedBranch: selectedBranchName)
                    case .tag(let tagName):
                        HistoryView(repositoryURL: repositoryURL, selectedBranch: tagName)
                    case .item(.search):
                        SearchView(repositoryURL: repositoryURL)
                    case .none:
                        EmptyStateView(message: "Select an item from the sidebar")
                    }
                }
```

- [ ] **Step 3: Update onChange handler for selectedItem**

Change lines 117-123:

```swift
        .onChange(of: selectedItem) { _, newItem in
            if case .branch(let name) = newItem {
                selectedBranchName = name
                selectedTagName = nil
            } else if case .tag(let name) = newItem {
                selectedTagName = name
                selectedBranchName = nil
            } else {
                selectedBranchName = nil
                selectedTagName = nil
            }
        }
```

- [ ] **Step 4: Add detached HEAD checkout confirmation state**

After line 27 (`@State private var branchToCheckout: String = ""`), add:

```swift
    @State private var showingDetachedHeadConfirmation = false
    @State private var tagToCheckout: String = ""
```

- [ ] **Step 5: Update checkout handler to distinguish branch vs tag**

Change the `onRequestCheckout` closure in `SidebarView` (lines 38-41):

```swift
                onRequestCheckout: { ref in
                    if selectedItem == .tag(ref) {
                        tagToCheckout = ref
                        showingDetachedHeadConfirmation = true
                    } else {
                        branchToCheckout = ref
                        showingCheckoutConfirmation = true
                    }
                }
```

- [ ] **Step 6: Add detached HEAD confirmation sheet**

After the existing `.sheet(isPresented: $showingCheckoutConfirmation)` block (line 191-197), add:

```swift
        .alert("Confirm change working copy", isPresented: $showingDetachedHeadConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("OK") {
                Task {
                    await performTagCheckout(tag: tagToCheckout)
                }
            }
        } message: {
            Text("Are you sure you want to checkout '\(tagToCheckout)'?\n\nDoing so will make your working copy a 'detached HEAD', which means you won't be on a branch anymore. If you want to commit after this you'll probably want to either checkout a branch again, or create a new branch. Is this ok?")
        }
```

- [ ] **Step 7: Add tag checkout helper**

After `performCheckout` (line 290), add:

```swift
    private func performTagCheckout(tag: String) async {
        do {
            try await GitStatusService.shared.checkoutCommit(tag, in: repositoryURL)
            await syncState.refresh(repositoryURL: repositoryURL)
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
        } catch {
            syncState.showError(error.localizedDescription)
        }
    }
```

- [ ] **Step 8: Verify build**

Build: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`
Expected: Clean build

- [ ] **Step 9: Commit**

```bash
git add macgit/Views/MainWindow/MainWindowView.swift
git commit -m "feat: wire tag selection and add detached HEAD checkout confirmation"
```

---

### Task 4: Verify end-to-end

- [ ] **Step 1: Launch app and open a repo with tags**

Run: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' run` (or run via Xcode)

- [ ] **Step 2: Verify tags appear in sidebar**

Expected: TAGS section shows tag names with `tag` icon

- [ ] **Step 3: Single-click a tag**

Expected: History view shows tag's commit, scrolls to it

- [ ] **Step 4: Double-click a tag**

Expected: Alert appears with detached HEAD warning message

- [ ] **Step 5: Click OK in alert**

Expected: Repo checks out tag, working copy is in detached HEAD state

- [ ] **Step 6: Commit all changes**

```bash
git log --oneline -5
```

Expected: 3 commits from the implementation plan

---

## Spec Coverage Check

| Spec Requirement | Task |
|-----------------|------|
| `tags()` and `tagCommitHash()` methods | Task 1 |
| `.tag(String)` in `SidebarSelection` | Task 2 |
| TAGS section renders real tag list | Task 2 |
| Single-click shows tag commit in history | Task 2 + Task 3 |
| Double-click shows detached HEAD confirmation | Task 3 |
| Minimal context menu (Copy tag name) | Task 2 |

## Placeholder Scan

- No "TBD" or "TODO" entries
- All code blocks contain complete, compilable code
- All file paths are exact
- No "similar to Task N" references

## Type Consistency Check

- `SidebarSelection.tag(String)` used consistently across all tasks
- `BranchNode` and `BranchRowItem` reused for tag tree (same as branch)
- `onRequestCheckout` closure signature unchanged — parameter is a string ref name

---

**Plan complete and saved to `docs/superpowers/plans/2026-06-12-tags-sidebar.md`.**

Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration
2. **Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
