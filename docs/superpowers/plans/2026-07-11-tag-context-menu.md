# Tag Context Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add functional Checkout, Details, Diff Against Current, Push to, and Delete actions to sidebar tag rows while preserving the existing copy action.

**Architecture:** Add focused tag metadata/deletion APIs to `GitStatusService` and extend `PushOptions` so the existing credential-aware push path can push one named tag. Keep context-menu rendering in `SidebarView`; route sheet presentation and repository operations through `MainWindowView`, using a small reusable `TagDetailsSheet` for basic metadata.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Git subprocesses through `GitStatusService`.

## Global Constraints

- Every new Swift file must include the repository AGPL v3 header.
- Do not launch the app; verification ends after targeted tests and `xcodebuild ... build` succeed.
- Checkout must reuse the existing detached-HEAD confirmation flow.
- Push must send only the selected tag to the chosen remote.
- Delete must require destructive confirmation and remove only the local tag.

---

### Task 1: Tag metadata and local deletion services

**Files:**
- Create: `macgit/Services/GitTagDetails.swift`
- Create: `macgit/Services/GitStatusService+Tag.swift`
- Create: `macgitTests/GitTagServiceTests.swift`

**Interfaces:**
- Produces: `nonisolated struct GitTagDetails: Equatable, Sendable`
- Produces: `func tagDetails(name:in:) async throws -> GitTagDetails`
- Produces: `func deleteTag(name:in:) async throws`

- [ ] **Step 1: Write failing integration tests**

Create temporary Git repositories and assert that a lightweight tag resolves to the tagged commit's hash, author, email, date, subject/body, and that deleting a tag removes it from `tags(in:)`. Add an annotated-tag case proving `^{commit}` peeling returns commit metadata rather than tag-object metadata.

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitTagServiceTests test
```

Expected: compilation fails because `GitTagDetails`, `tagDetails`, and `deleteTag` do not exist.

- [ ] **Step 3: Implement the model and service methods**

Define:

```swift
nonisolated struct GitTagDetails: Equatable, Sendable {
    let name: String
    let commitHash: String
    let authorName: String
    let authorEmail: String
    let date: Date
    let subject: String
    let body: String
}
```

Resolve metadata with one delimiter-safe command:

```swift
git show -s --format=%H%x00%an%x00%ae%x00%aI%x00%s%x00%b <tag>^{commit}
```

Parse exactly six NUL-delimited fields with `ISO8601DateFormatter`; throw `GitError.commandFailed` for malformed output/date. Delete with:

```swift
try await runGit(arguments: ["tag", "-d", name], in: repositoryURL)
```

- [ ] **Step 4: Run the targeted tests and verify GREEN**

Run the Task 1 command again. Expected: all `GitTagServiceTests` pass.

- [ ] **Step 5: Commit Task 1**

```bash
git add macgit/Services/GitTagDetails.swift macgit/Services/GitStatusService+Tag.swift macgitTests/GitTagServiceTests.swift
git commit -m "feat: add tag metadata and deletion services"
```

---

### Task 2: Push one selected tag through the existing remote path

**Files:**
- Modify: `macgit/Services/GitStatusService.swift`
- Modify: `macgit/Services/GitStatusService+Remote.swift`
- Create: `macgitTests/GitTagPushServiceTests.swift`

**Interfaces:**
- Extends: `GitStatusService.PushOptions` with `var tags: [String] = []`
- Consumes: existing credential-aware `GitStatusService.push(options:in:credentialResolver:...)`

- [ ] **Step 1: Write a failing push integration test**

Create a local source repository and a bare remote, create tags `v1` and `v2`, call:

```swift
let options = GitStatusService.PushOptions(remote: "origin", tags: ["v1"])
try await GitStatusService.shared.push(options: options, in: sourceURL)
```

Assert `refs/tags/v1` exists in the bare remote and `refs/tags/v2` does not.

- [ ] **Step 2: Run the test and verify RED**

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitTagPushServiceTests test
```

Expected: compilation fails because `PushOptions` has no `tags` member.

- [ ] **Step 3: Implement named-tag refspec pushes**

Add `tags` to `PushOptions`. In `push(options:...)`, before the existing `pushTags` all-tags block, push each selected tag with an explicit refspec:

```swift
for tag in options.tags {
    let ref = "refs/tags/\(tag)"
    let output = try await runRemoteGit(
        arguments: ["push", options.remote, "\(ref):\(ref)"],
        in: repositoryURL,
        injection: injection
    )
    outputs.append(output)
}
```

Keep `pushTags` unchanged for the existing Push sheet.

- [ ] **Step 4: Run targeted tests and verify GREEN**

Run the Task 2 test command. Expected: the named-tag-only assertions pass.

- [ ] **Step 5: Commit Task 2**

```bash
git add macgit/Services/GitStatusService.swift macgit/Services/GitStatusService+Remote.swift macgitTests/GitTagPushServiceTests.swift
git commit -m "feat: support pushing a selected tag"
```

---

### Task 3: Basic tag details sheet

**Files:**
- Create: `macgit/Views/Common/TagDetailsSheet.swift`
- Create: `macgitTests/TagDetailsPresentationTests.swift`

**Interfaces:**
- Produces: `struct TagDetailsSheet: View` initialized with `GitTagDetails` and `onDismiss: () -> Void`
- Produces: `nonisolated struct TagDetailsPresentation: Equatable` for deterministic display text/date formatting tests

- [ ] **Step 1: Write failing presentation tests**

Construct fixed `GitTagDetails` input and assert presentation values include the full hash, `Author Name <email>`, a non-empty localized date string, subject, and body. Add a body-empty case that does not introduce an extra blank content block.

- [ ] **Step 2: Run the tests and verify RED**

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/TagDetailsPresentationTests test
```

Expected: compilation fails because `TagDetailsPresentation` does not exist.

- [ ] **Step 3: Implement presentation and sheet**

Build a compact SwiftUI sheet with title `Tag details`, the tag name, commit hash, author, date, and commit message. Use selectable text for hash and metadata, `ScrollView` for long messages, a minimum width near 420 points, and one default **OK** button that calls `onDismiss`.

- [ ] **Step 4: Run presentation tests and verify GREEN**

Run the Task 3 test command. Expected: all presentation assertions pass.

- [ ] **Step 5: Commit Task 3**

```bash
git add macgit/Views/Common/TagDetailsSheet.swift macgitTests/TagDetailsPresentationTests.swift
git commit -m "feat: add basic tag details sheet"
```

---

### Task 4: Wire the sidebar tag context menu

**Files:**
- Modify: `macgit/Views/MainWindow/SidebarView.swift`
- Modify: `macgit/Views/MainWindow/MainWindowView.swift`

**Interfaces:**
- Adds Sidebar callbacks: `onRequestTagDetails`, `onRequestDiffTagAgainstCurrent`, `onRequestPushTagToRemote`, and `onRequestDeleteTag`
- Consumes: `tagDetails(name:in:)`, `deleteTag(name:in:)`, and `PushOptions(tags:)`

- [ ] **Step 1: Add callback plumbing and MainWindow state**

Add defaulted callbacks to `SidebarView` so previews and existing call sites remain source-compatible. In `MainWindowView`, add optional details/loading state, tag deletion confirmation state, and sheet/alert bindings.

- [ ] **Step 2: Render the exact context-menu order**

Extract `tagContextMenu(for:)` and render:

```swift
Button("Copy Tag Name to Clipboard") { ... }
Divider()
Button("Checkout \(tag)") { onRequestCheckout(tag, true) }
Button("Details...") { onRequestTagDetails(tag) }
Divider()
Button("Diff Against Current") { onRequestDiffTagAgainstCurrent(tag) }
Divider()
Menu("Push to") { /* remoteNames buttons */ }
Button("Delete \(tag)", role: .destructive) { onRequestDeleteTag(tag) }
```

Disable Push to when `remoteNames` is empty.

- [ ] **Step 3: Implement the four MainWindow callbacks**

- Details: load `tagDetails`, then present `TagDetailsSheet`; route load errors through `SyncState`'s existing error UI.
- Diff: set `selectedItem = .tag(tag)` so the existing History view loads the tag and its commit diff experience.
- Push: call `syncState.performPush` with `PushOptions(remote: remote, tags: [tag])` and the provider credential resolver.
- Delete: present a destructive alert naming the tag; on confirmation call `deleteTag`, select History if needed, refresh `SyncState`, and post `.repositoryDidChange` only after success.

- [ ] **Step 4: Run focused regression tests**

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitTagServiceTests -only-testing:macgitTests/GitTagPushServiceTests -only-testing:macgitTests/TagDetailsPresentationTests test
```

Expected: all tag tests pass.

- [ ] **Step 5: Build the app**

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```

Expected: `** BUILD SUCCEEDED **`. Do not launch the app.

- [ ] **Step 6: Commit Task 4**

```bash
git add macgit/Views/MainWindow/SidebarView.swift macgit/Views/MainWindow/MainWindowView.swift
git commit -m "feat: expand sidebar tag context menu"
```
