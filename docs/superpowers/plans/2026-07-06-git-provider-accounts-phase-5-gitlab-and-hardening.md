# Git Provider Accounts Phase 5 GitLab and Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GitLab support through the same provider-account architecture and document the backend requirements that remain for GitHub App installation tokens, webhooks, and organization policy.

**Architecture:** GitLab adds provider-specific auth, remote parsing, and PR-equivalent merge request APIs without changing the shared token vault, controller, credential injection, or PR UI contracts. Backend hardening is recorded as an explicit follow-up plan only for flows that require confidential server-owned secrets.

**Tech Stack:** Swift, SwiftUI, `URLSession`, GitLab OAuth with PKCE, GitLab REST API, XCTest fake HTTP clients, `xcodebuild`.

---

## File Structure

- Create `macgit/Services/GitLabProviderAuthService.swift`: GitLab OAuth and profile adapter.
- Create `macgit/Services/GitLabPullRequestService.swift`: GitLab merge request adapter behind `PullRequestProviding`.
- Modify `macgit/Services/GitRemoteIdentityResolver.swift`: complete GitLab.com and self-hosted path handling.
- Modify `macgit/Views/Account/GitProviderAccountsSection.swift`: add GitLab account action and self-hosted host entry.
- Create `docs/superpowers/plans/2026-07-06-git-provider-backend-hardening-followup.md`: backend-only follow-up if required by selected production provider configuration.
- Test with `GitLabProviderAuthServiceTests.swift`, `GitLabPullRequestServiceTests.swift`, and updated resolver/UI tests.

### Task 1: Add GitLab Auth Service

**Files:**
- Create: `macgit/Services/GitLabProviderAuthService.swift`
- Test: `macgitTests/GitLabProviderAuthServiceTests.swift`

- [x] **Step 1: Write GitLab auth tests**

Use fake HTTP responses and cover:

```swift
func testAuthorizationURLIncludesPKCEChallenge()
func testTokenExchangeUsesConfiguredHost()
func testProfileResponseCreatesGitLabProviderAccount()
func testSelfHostedHostIsPreserved()
func testUnauthorizedMapsToReauthorizationRequired()
```

- [x] **Step 2: Implement GitLab adapter**

`GitLabProviderAuthService` must:

- Use the configured host for authorize, token, and user endpoints.
- Include `client_id`, `redirect_uri`, `response_type=code`, `state`, `code_challenge`, and `code_challenge_method=S256`.
- Exchange with `code_verifier`.
- Fetch the current user profile.
- Save `GitProviderAccount(provider: .gitlab, hostURL: configuredHost.baseURL, ...)`.

- [x] **Step 3: Run focused tests and commit**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitLabProviderAuthServiceTests test
```

Expected: tests pass with fake HTTP.

```bash
git add macgit/Services/GitLabProviderAuthService.swift macgitTests/GitLabProviderAuthServiceTests.swift
git commit -m "feat: add gitlab provider auth"
```

### Task 2: Add GitLab Merge Request Service

**Files:**
- Create: `macgit/Services/GitLabPullRequestService.swift`
- Modify: `macgit/Services/GitRemoteIdentityResolver.swift`
- Test: `macgitTests/GitLabPullRequestServiceTests.swift`

- [x] **Step 1: Write GitLab MR tests**

Cover:

```swift
func testListMergeRequestsDecodesOpenItems()
func testCreateMergeRequestPostsExpectedBody()
func testRepositoryPathIsURLEncodedForSubgroups()
func testForbiddenMapsToPermissionDenied()
```

- [x] **Step 2: Implement GitLab service**

Use:

```text
GET /api/v4/projects/{urlEncodedPath}/merge_requests?state=opened
POST /api/v4/projects/{urlEncodedPath}/merge_requests
POST /api/v4/projects/{urlEncodedPath}/merge_requests/{iid}/notes
```

Map GitLab merge requests into existing `PullRequestSummary` values so UI does not branch on provider.

- [x] **Step 3: Run focused tests and commit**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitLabPullRequestServiceTests test
```

Expected: tests pass with fake HTTP.

```bash
git add macgit/Services/GitLabPullRequestService.swift macgit/Services/GitRemoteIdentityResolver.swift macgitTests/GitLabPullRequestServiceTests.swift
git commit -m "feat: add gitlab merge request service"
```

### Task 3: Add GitLab UI Entry and Backend Follow-Up Decision

**Files:**
- Modify: `macgit/Views/Account/GitProviderAccountsSection.swift`
- Modify: `macgit/App/GitProviderAccountController.swift`
- Create: `docs/superpowers/plans/2026-07-06-git-provider-backend-hardening-followup.md`
- Test: updated provider account UI tests.

- [x] **Step 1: Add UI tests**

Cover:

```swift
func testSignedInUserSeesAddGitHubAndAddGitLabActions()
func testSelfHostedGitLabRequiresHostURL()
func testGitLabAccountUsesSameDisconnectFlowAsGitHub()
```

- [x] **Step 2: Implement GitLab account entry**

Add:

- `Add GitHub Account...`
- `Add GitLab.com Account...`
- `Add Self-Hosted GitLab Account...`

Self-hosted GitLab prompts for a host URL, normalizes it, and starts GitLab OAuth against that host.

- [x] **Step 3: Write backend hardening follow-up**

Create `docs/superpowers/plans/2026-07-06-git-provider-backend-hardening-followup.md` with concrete triggers:

- GitHub App installation-token minting.
- GitHub App private key custody.
- Provider webhooks.
- Org/team policy enforcement.
- Cross-device provider token sync.
- Server-side token refresh rotation.

State that Firebase Functions or Cloud Run requires Blaze billing when deployed, and that the client-only roadmap remains usable without it.

- [x] **Step 4: Run tests, build, and full suite**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitProviderAccountsSectionTests test
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test
```

Expected: all commands pass. Do not launch the app.

- [x] **Step 5: Update roadmap and commit**

Update the roadmap Phase 5 entry to `[completed]` with the branch or merge commit.

```bash
git add macgit/Views/Account/GitProviderAccountsSection.swift macgit/App/GitProviderAccountController.swift docs/superpowers/plans/2026-07-06-git-provider-backend-hardening-followup.md docs/superpowers/plans/2026-07-06-git-provider-accounts-roadmap.md macgitTests/GitProviderAccountsSectionTests.swift
git commit -m "feat: add gitlab provider roadmap completion"
```
