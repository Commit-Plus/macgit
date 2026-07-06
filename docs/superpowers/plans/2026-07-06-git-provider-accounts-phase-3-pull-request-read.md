# Git Provider Accounts Phase 3 Pull Request Read Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add read-only pull request visibility for a repository using the connected provider account selected for that remote.

**Architecture:** Provider-specific API clients implement a shared `PullRequestProviding` protocol. UI consumes normalized `PullRequestSummary` values and stays independent of GitHub response JSON.

**Tech Stack:** Swift, SwiftUI, `URLSession`, existing remote URL parsing, XCTest with fake HTTP client, `xcodebuild`.

---

## File Structure

- Create `macgit/Models/PullRequestModels.swift`: normalized PR summary, author, branch refs, and state.
- Create `macgit/Services/PullRequestProviding.swift`: provider protocol and API errors.
- Create `macgit/Services/GitHubPullRequestService.swift`: GitHub REST adapter.
- Create `macgit/App/PullRequestController.swift`: repository-scoped PR loading state.
- Create `macgit/Views/PullRequests/PullRequestListView.swift`: PR list, empty state, loading, auth error, open-in-browser.
- Modify `macgit/Views/MainWindow/MainWindowView.swift`: add PR entry point for provider-backed repositories.
- Test with `PullRequestModelsTests.swift`, `GitHubPullRequestServiceTests.swift`, and `PullRequestControllerTests.swift`.

### Task 1: Add Pull Request Models

**Files:**
- Create: `macgit/Models/PullRequestModels.swift`
- Test: `macgitTests/PullRequestModelsTests.swift`

- [ ] **Step 1: Write model tests**

Cover:

```swift
func testPullRequestSummaryUsesNumberAsStableID()
func testDraftRejectsSameSourceAndTargetBranch()
func testRepositoryIdentityBuildsBrowserURLForGitHub()
```

- [ ] **Step 2: Implement models**

Create:

```swift
enum PullRequestState: String, Codable, Equatable {
    case open
    case closed
    case merged
    case draft
}

struct PullRequestAuthor: Equatable, Codable {
    var username: String
    var avatarURL: URL?
}

struct PullRequestBranchRef: Equatable, Codable {
    var label: String
    var ref: String
    var sha: String?
}

struct PullRequestSummary: Identifiable, Equatable, Codable {
    var id: Int { number }
    var number: Int
    var title: String
    var state: PullRequestState
    var author: PullRequestAuthor
    var source: PullRequestBranchRef
    var target: PullRequestBranchRef
    var webURL: URL
    var updatedAt: Date
}

struct PullRequestDraft: Equatable {
    var repository: GitRepositoryIdentity
    var sourceBranch: String
    var targetBranch: String
    var title: String
    var body: String
}
```

- [ ] **Step 3: Run model tests and commit**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/PullRequestModelsTests test
```

Expected: model tests pass.

```bash
git add macgit/Models/PullRequestModels.swift macgitTests/PullRequestModelsTests.swift
git commit -m "feat: add pull request models"
```

### Task 2: Add GitHub PR Read Service

**Files:**
- Create: `macgit/Services/PullRequestProviding.swift`
- Create: `macgit/Services/GitHubPullRequestService.swift`
- Test: `macgitTests/GitHubPullRequestServiceTests.swift`

- [ ] **Step 1: Write API decoding tests**

Use fake HTTP responses and cover:

```swift
func testListPullRequestsDecodesOpenGitHubPRs()
func testDraftGitHubPRDecodesAsDraftState()
func testUnauthorizedMapsToReauthorizationRequired()
func testForbiddenMapsToPermissionDenied()
func testNotFoundMapsToRepositoryUnavailable()
```

- [ ] **Step 2: Implement protocol and errors**

Add:

```swift
protocol PullRequestProviding {
    func listPullRequests(repository: GitRepositoryIdentity, token: GitProviderToken) async throws -> [PullRequestSummary]
}

enum PullRequestProviderError: LocalizedError, Equatable {
    case reauthorizationRequired
    case permissionDenied
    case repositoryUnavailable
    case unsupportedProvider
    case providerMessage(String)
}
```

- [ ] **Step 3: Implement GitHub list adapter**

Call:

```text
GET https://api.github.com/repos/{owner}/{repo}/pulls?state=open
```

Headers:

- `Accept: application/vnd.github+json`
- `Authorization: Bearer <token>`

Decode only fields needed for `PullRequestSummary`.

- [ ] **Step 4: Run API tests and commit**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitHubPullRequestServiceTests test
```

Expected: service tests pass without real network.

```bash
git add macgit/Services/PullRequestProviding.swift macgit/Services/GitHubPullRequestService.swift macgitTests/GitHubPullRequestServiceTests.swift
git commit -m "feat: list github pull requests"
```

### Task 3: Add PR Controller and Read UI

**Files:**
- Create: `macgit/App/PullRequestController.swift`
- Create: `macgit/Views/PullRequests/PullRequestListView.swift`
- Modify: `macgit/Views/MainWindow/MainWindowView.swift`
- Test: `macgitTests/PullRequestControllerTests.swift`

- [ ] **Step 1: Write controller tests**

Cover:

```swift
func testLoadPullRequestsRequiresConnectedProviderAccount()
func testLoadPullRequestsPublishesResults()
func testLoadPullRequestsPublishesPermissionError()
func testOpenInBrowserUsesPullRequestWebURL()
```

- [ ] **Step 2: Implement controller**

`PullRequestController` accepts:

- Repository URL or remote URL.
- `GitRemoteIdentityResolver`.
- `GitProviderAccountController`.
- `GitProviderTokenVault`.
- Provider service registry.

Publish:

- `items: [PullRequestSummary]`
- `isLoading`
- `errorMessage`
- `selectedProviderAccountID`

- [ ] **Step 3: Implement list view**

Render:

- Loading indicator.
- Empty state: `No open pull requests`.
- Error state with `Connect Account...` or `Reconnect...` when auth is missing.
- Rows with PR number, title, source -> target, author, updated time, and open-in-browser button.

- [ ] **Step 4: Run focused tests, build, and full suite**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/PullRequestControllerTests test
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test
```

Expected: all commands pass. Do not launch the app.

- [ ] **Step 5: Update roadmap and commit**

Update the roadmap Phase 3 entry to `[completed]` with the branch or merge commit.

```bash
git add macgit/App/PullRequestController.swift macgit/Views/PullRequests/PullRequestListView.swift macgit/Views/MainWindow/MainWindowView.swift macgitTests/PullRequestControllerTests.swift docs/superpowers/plans/2026-07-06-git-provider-accounts-roadmap.md
git commit -m "feat: show repository pull requests"
```
