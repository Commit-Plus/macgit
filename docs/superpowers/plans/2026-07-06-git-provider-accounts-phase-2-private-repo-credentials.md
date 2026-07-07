# Git Provider Accounts Phase 2 Private Repository Credentials Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Use connected provider accounts for private HTTPS Git fetch, pull, push, clone, and remote operations without exposing tokens in URLs, command arguments, logs, or UI state.

**Architecture:** Remote URL parsing maps a repository remote to a provider account. A Git credential injector supplies username/token through environment-only askpass helpers to the existing `Process()` Git runner.

**Tech Stack:** Swift, XCTest temp Git repositories, existing `GitStatusService`, `Process()` environment injection, macOS file permissions, `xcodebuild`.

---

## File Structure

- Create `macgit/Services/GitRemoteIdentityResolver.swift`: parse GitHub/GitLab remote URLs into provider repository identity.
- Create `macgit/Services/GitCredentialInjector.swift`: temporary askpass helper creation and Git environment merging.
- Modify `macgit/Services/GitCommandRunning.swift`: allow per-command environment overrides if the current runner does not already support them.
- Modify `macgit/Services/GitStatusService+Remote.swift`: use credential injection for provider-backed remote actions.
- Modify clone/open-repository service files if clone support already has a central path.
- Test with `GitRemoteIdentityResolverTests.swift`, `GitCredentialInjectorTests.swift`, and focused remote-operation tests.

### Task 1: Parse Provider Remote Identities

**Files:**
- Create: `macgit/Services/GitRemoteIdentityResolver.swift`
- Test: `macgitTests/GitRemoteIdentityResolverTests.swift`

- [x] **Step 1: Write resolver tests**

Cover:

```swift
func testParsesHttpsGitHubRemote()
func testParsesSshGitHubRemote()
func testParsesGitLabSubgroupRemote()
func testUnsupportedHostReturnsNil()
func testRemoteWithoutRepositoryNameReturnsNil()
```

Use examples:

- `https://github.com/octocat/Hello-World.git`
- `git@github.com:octocat/Hello-World.git`
- `https://gitlab.com/group/subgroup/project.git`

- [x] **Step 2: Implement resolver**

Return:

```swift
struct GitRemoteIdentity: Equatable {
    var provider: GitProviderKind
    var hostURL: URL
    var ownerPath: String
    var repositoryName: String
    var canonicalHTTPSURL: URL
}
```

For GitHub, `ownerPath` is one segment. For GitLab, `ownerPath` can include subgroups.

- [x] **Step 3: Run resolver tests and commit**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitRemoteIdentityResolverTests test
```

Expected: tests pass.

```bash
git add macgit/Services/GitRemoteIdentityResolver.swift macgitTests/GitRemoteIdentityResolverTests.swift
git commit -m "feat: resolve git provider remotes"
```

### Task 2: Add Credential Injection

**Files:**
- Create: `macgit/Services/GitCredentialInjector.swift`
- Modify: `macgit/Services/GitCommandRunning.swift`
- Test: `macgitTests/GitCredentialInjectorTests.swift`

- [x] **Step 1: Write injector tests**

Cover:

```swift
func testEnvironmentSetsGitTerminalPromptToZero()
func testAskpassHelperDoesNotContainTokenInFileName()
func testAskpassHelperReturnsUsernameForUsernamePrompt()
func testAskpassHelperReturnsTokenForPasswordPrompt()
func testCleanupRemovesHelperFile()
```

- [x] **Step 2: Implement injector**

Create:

```swift
struct GitCredential {
    var username: String
    var token: String
}

struct GitCredentialInjection {
    var environment: [String: String]
    var cleanup: () -> Void
}

protocol GitCredentialInjecting {
    func injection(for credential: GitCredential) throws -> GitCredentialInjection
}
```

The production helper:

- Writes a temporary executable script with `0700` permissions.
- Stores username/token in a temporary protected file or environment variable that is not logged.
- Sets `GIT_TERMINAL_PROMPT=0`.
- Sets `GIT_ASKPASS` to the helper path.
- Removes temporary files in `cleanup`.

- [x] **Step 3: Allow command environment overrides**

If `GitCommandRunning` does not currently accept environment overrides, add an overload that merges extra environment values into the subprocess environment while preserving existing behavior for callers that do not pass credentials.

- [x] **Step 4: Run injector tests and commit**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitCredentialInjectorTests test
```

Expected: tests pass.

```bash
git add macgit/Services/GitCredentialInjector.swift macgit/Services/GitCommandRunning.swift macgitTests/GitCredentialInjectorTests.swift
git commit -m "feat: inject provider git credentials"
```

### Task 3: Use Provider Credentials for Remote Git Actions

**Files:**
- Modify: `macgit/Services/GitStatusService+Remote.swift`
- Modify: remote action callers in `macgit/Views/MainWindow/MainWindowView.swift` only if credentials must be selected before action execution.
- Test: focused remote service tests using fake credential injector.

- [x] **Step 1: Add tests for credential-aware remote actions**

Cover fetch and push paths with a fake runner:

```swift
func testFetchRemoteUsesCredentialEnvironmentWhenProviderAccountSelected()
func testPushBranchUsesCredentialEnvironmentWhenProviderAccountSelected()
func testRemoteActionWithoutProviderAccountKeepsExistingBehavior()
func testMissingTokenReturnsUserFacingAuthenticationError()
```

- [x] **Step 2: Add provider account selection seam**

Create a small resolver that accepts:

- Repository remote URL.
- Connected accounts from `GitProviderAccountController`.
- Token vault.
- Optional repository-specific preferred account ID.

Return either a `GitCredential` or a typed error:

```swift
enum GitProviderCredentialError: LocalizedError, Equatable {
    case noConnectedAccount(host: String)
    case multipleMatchingAccounts(host: String)
    case tokenUnavailable(username: String)
    case unsupportedRemote
}
```

- [x] **Step 3: Wire fetch, pull, and push**

Use credential injection for HTTPS remotes that resolve to a connected provider account. Preserve existing behavior for local file remotes, unsupported hosts, and SSH remotes until SSH credential support is explicitly designed.

- [x] **Step 4: Run targeted and full tests**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitRemoteIdentityResolverTests -only-testing:macgitTests/GitCredentialInjectorTests test
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test
```

Expected: targeted and full test suites pass.

- [x] **Step 5: Update roadmap and commit**

Update the roadmap Phase 2 entry to `[completed]` with the branch or merge commit.

```bash
git add macgit/Services/GitStatusService+Remote.swift macgit/Views/MainWindow/MainWindowView.swift macgitTests docs/superpowers/plans/2026-07-06-git-provider-accounts-roadmap.md
git commit -m "feat: use provider credentials for remote git"
```
