# Git Provider Accounts Phase 4 Pull Request Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add core pull request actions: create PR from a local branch, checkout PR branch, and add a simple PR comment when provider permissions allow it.

**Architecture:** Write actions extend the Phase 3 provider protocol and controller. UI actions validate local branch and provider permission before sending API requests or running Git.

**Tech Stack:** Swift, SwiftUI, `URLSession`, existing branch/remote Git services, XCTest temp repositories, `xcodebuild`.

---

## File Structure

- Modify `macgit/Services/PullRequestProviding.swift`: add create/comment capabilities.
- Modify `macgit/Services/GitHubPullRequestService.swift`: implement GitHub create and comment endpoints.
- Create `macgit/Views/PullRequests/CreatePullRequestSheet.swift`: source/target/title/body form.
- Modify `macgit/App/PullRequestController.swift`: create/comment/checkout intents.
- Modify `macgit/Views/PullRequests/PullRequestListView.swift`: action buttons and row menu.
- Modify `macgit/Services/GitStatusService+Remote.swift`: fetch PR ref when checkout requires provider-specific refs.
- Test with `GitHubPullRequestWriteServiceTests.swift`, `CreatePullRequestDraftTests.swift`, and `PullRequestActionControllerTests.swift`.

### Task 1: Add Create PR Draft and Validation

**Files:**
- Modify: `macgit/Models/PullRequestModels.swift`
- Create: `macgitTests/CreatePullRequestDraftTests.swift`

- [ ] **Step 1: Write validation tests**

Cover:

```swift
func testDraftRequiresTitle()
func testDraftRejectsSameSourceAndTargetBranch()
func testDraftAcceptsDifferentBranches()
```

- [ ] **Step 2: Implement validation**

Add:

```swift
enum PullRequestDraftValidationError: LocalizedError, Equatable {
    case emptyTitle
    case sameSourceAndTargetBranch
}

extension PullRequestDraft {
    func validate() throws {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw PullRequestDraftValidationError.emptyTitle
        }
        if sourceBranch == targetBranch {
            throw PullRequestDraftValidationError.sameSourceAndTargetBranch
        }
    }
}
```

- [ ] **Step 3: Run draft tests and commit**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/CreatePullRequestDraftTests test
```

Expected: validation tests pass.

```bash
git add macgit/Models/PullRequestModels.swift macgitTests/CreatePullRequestDraftTests.swift
git commit -m "feat: validate pull request drafts"
```

### Task 2: Add GitHub Write Actions

**Files:**
- Modify: `macgit/Services/PullRequestProviding.swift`
- Modify: `macgit/Services/GitHubPullRequestService.swift`
- Test: `macgitTests/GitHubPullRequestWriteServiceTests.swift`

- [ ] **Step 1: Write service tests**

Cover:

```swift
func testCreatePullRequestPostsExpectedBody()
func testCreatePullRequestDecodesCreatedSummary()
func testCreatePullRequestPermissionDeniedMapsToUserFacingError()
func testCreateCommentPostsExpectedBody()
```

- [ ] **Step 2: Extend protocol**

Add:

```swift
func createPullRequest(_ draft: PullRequestDraft, token: GitProviderToken) async throws -> PullRequestSummary
func createComment(body: String, pullRequest: PullRequestSummary, repository: GitRepositoryIdentity, token: GitProviderToken) async throws
```

- [ ] **Step 3: Implement GitHub endpoints**

Use:

```text
POST https://api.github.com/repos/{owner}/{repo}/pulls
POST https://api.github.com/repos/{owner}/{repo}/issues/{number}/comments
```

Headers:

- `Accept: application/vnd.github+json`
- `Authorization: Bearer <token>`

Do not log request bodies when they include user comments.

- [ ] **Step 4: Run write-service tests and commit**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitHubPullRequestWriteServiceTests test
```

Expected: write-service tests pass with fake HTTP.

```bash
git add macgit/Services/PullRequestProviding.swift macgit/Services/GitHubPullRequestService.swift macgitTests/GitHubPullRequestWriteServiceTests.swift
git commit -m "feat: add github pull request write actions"
```

### Task 3: Add Create PR UI and Controller Actions

**Files:**
- Create: `macgit/Views/PullRequests/CreatePullRequestSheet.swift`
- Modify: `macgit/App/PullRequestController.swift`
- Modify: `macgit/Views/PullRequests/PullRequestListView.swift`
- Test: `macgitTests/PullRequestActionControllerTests.swift`

- [ ] **Step 1: Write controller action tests**

Cover:

```swift
func testCreatePullRequestRequiresValidDraft()
func testCreatePullRequestRefreshesListAfterSuccess()
func testCommentRequiresNonEmptyBody()
func testCheckoutPRFetchesProviderRefWhenNeeded()
```

- [ ] **Step 2: Implement create sheet**

Fields:

- Source branch picker defaulting to current local branch.
- Target branch picker defaulting to repository default branch when available, otherwise `main`.
- Title field defaulting to source branch name converted to words.
- Body editor.
- Primary `Create Pull Request` button.
- Cancel button.

Disable the primary button while submitting or while validation fails.

- [ ] **Step 3: Implement controller actions**

Add intents:

- `presentCreatePullRequest()`
- `createPullRequest(_ draft: PullRequestDraft) async`
- `comment(on pullRequest: PullRequestSummary, body: String) async`
- `checkout(_ pullRequest: PullRequestSummary) async`

The checkout flow should use existing branch checkout behavior when the PR source branch is available locally. For GitHub PRs from forks, fetch `pull/{number}/head` into a local branch name such as `pr/{number}` before checkout.

- [ ] **Step 4: Run focused tests, build, and full suite**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/PullRequestActionControllerTests test
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test
```

Expected: all commands pass. Do not launch the app.

- [ ] **Step 5: Update roadmap and commit**

Update the roadmap Phase 4 entry to `[completed]` with the branch or merge commit.

```bash
git add macgit/Views/PullRequests/CreatePullRequestSheet.swift macgit/App/PullRequestController.swift macgit/Views/PullRequests/PullRequestListView.swift macgitTests/PullRequestActionControllerTests.swift docs/superpowers/plans/2026-07-06-git-provider-accounts-roadmap.md
git commit -m "feat: add pull request actions"
```
