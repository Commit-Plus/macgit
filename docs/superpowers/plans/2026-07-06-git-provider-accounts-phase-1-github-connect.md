# Git Provider Accounts Phase 1 GitHub Connect Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a signed-in macgit user connect and disconnect a GitHub account through GitHub OAuth App Device Flow, saving tokens to Keychain and metadata through the Phase 0 controller.

**Architecture:** A provider-auth protocol owns device-code authorization, token polling, and profile fetch. SwiftUI renders provider account settings and the short user code; it never handles raw tokens.

**Tech Stack:** Swift, SwiftUI, AppKit URL opening, GitHub OAuth Device Flow endpoints, `URLSession`, XCTest, `xcodebuild`.

---

## File Structure

- Create `macgit/Services/GitProviderOAuthModels.swift`: OAuth callback/PKCE support kept as reusable model groundwork.
- Create `macgit/Services/GitHubProviderAuthService.swift`: device-code request, token polling, and `/user` profile fetch.
- Create `macgit/Views/Account/GitProviderAccountsSection.swift`: connected account list and add/remove actions.
- Modify `macgit/Views/Account/ManageAccountSheet.swift`: show provider accounts below macgit account controls.
- Modify `macgit/App/macgitApp.swift`: wire provider account controller and open GitHub device verification URLs externally.
- Test with `GitProviderOAuthTests.swift`, `GitHubProviderAuthServiceTests.swift`, and `GitProviderAccountsSectionTests.swift`.

### Task 1: Add OAuth Session and PKCE Models

**Files:**
- Create: `macgit/Services/GitProviderOAuthModels.swift`
- Test: `macgitTests/GitProviderOAuthTests.swift`

- [ ] **Step 1: Write PKCE tests**

Cover:

```swift
func testPKCEVerifierUsesAllowedCharacters()
func testPKCEChallengeIsBase64URLWithoutPadding()
func testCallbackRejectsMismatchedState()
func testCallbackExtractsAuthorizationCode()
```

- [ ] **Step 2: Implement OAuth models**

Create:

```swift
struct GitProviderOAuthSession: Equatable {
    var provider: GitProviderKind
    var host: GitProviderHost
    var state: String
    var codeVerifier: String
    var redirectURI: URL
}

struct GitProviderOAuthCallback: Equatable {
    var code: String
    var state: String
}

enum GitProviderOAuthError: LocalizedError, Equatable {
    case missingCode
    case missingState
    case stateMismatch
    case unsupportedCallback
    case providerMessage(String)
}
```

Add `GitProviderPKCE.generateVerifier()` and `GitProviderPKCE.challenge(for:)` using SHA-256 and base64url encoding without padding.

- [ ] **Step 3: Run focused OAuth tests**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitProviderOAuthTests test
```

Expected: PKCE and callback parsing tests pass.

- [ ] **Step 4: Commit**

```bash
git add macgit/Services/GitProviderOAuthModels.swift macgitTests/GitProviderOAuthTests.swift
git commit -m "feat: add provider oauth session models"
```

### Task 2: Add GitHub Provider Auth Service

**Files:**
- Create: `macgit/Services/GitHubProviderAuthService.swift`
- Test: `macgitTests/GitHubProviderAuthServiceTests.swift`

- [ ] **Step 1: Write URL-construction and response-decoding tests**

Use a fake `URLProtocol` or injectable HTTP client and cover:

```swift
func testAuthorizationURLIncludesClientIDRedirectStateAndPKCEChallenge()
func testTokenExchangeSendsCodeVerifier()
func testProfileResponseCreatesProviderAccountMetadata()
func testHTTPUnauthorizedMapsToReauthorizationRequired()
```

- [ ] **Step 2: Implement provider auth protocol**

Add:

```swift
protocol GitProviderAuthenticating {
    func authorizationURL(for session: GitProviderOAuthSession) throws -> URL
    func exchangeCallback(_ callback: GitProviderOAuthCallback, session: GitProviderOAuthSession) async throws -> GitProviderToken
    func fetchAccount(token: GitProviderToken, macgitUID: String, host: GitProviderHost) async throws -> GitProviderAccount
}
```

- [ ] **Step 3: Implement GitHub adapter**

`GitHubProviderAuthService` must:

- Build `https://github.com/login/oauth/authorize`.
- Include `client_id`, `redirect_uri`, `state`, `scope`, `code_challenge`, and `code_challenge_method=S256`.
- Exchange the code at the configured GitHub token endpoint.
- Send `Accept: application/json`.
- Fetch `https://api.github.com/user`.
- Create `GitProviderAccount` with `provider = .github`, `hostURL = https://github.com`, `providerUserID`, `username`, `displayName`, `avatarURL`, scopes, permissions, and `tokenStatus = .valid`.

Configuration must come from an app-owned config type, not hard-coded secrets:

```swift
struct GitHubProviderAuthConfiguration {
    var clientID: String
    var redirectURI: URL
    var scopes: [String]
}
```

- [ ] **Step 4: Run focused GitHub auth tests**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitHubProviderAuthServiceTests test
```

Expected: tests pass with fake HTTP responses; no real network request is made.

- [ ] **Step 5: Commit**

```bash
git add macgit/Services/GitHubProviderAuthService.swift macgitTests/GitHubProviderAuthServiceTests.swift
git commit -m "feat: add github provider auth service"
```

### Task 3: Add Provider Accounts UI

**Files:**
- Create: `macgit/Views/Account/GitProviderAccountsSection.swift`
- Modify: `macgit/Views/Account/ManageAccountSheet.swift`
- Modify: `macgit/App/macgitApp.swift`
- Test: `macgitTests/GitProviderAccountsSectionTests.swift`

- [ ] **Step 1: Write presentation-policy tests**

Create a pure policy helper if needed and cover:

```swift
func testGuestCannotConnectProviderUntilSignedIn()
func testSignedInUserSeesAddGitHubAction()
func testUnavailableOnDeviceShowsReconnectAction()
func testValidAccountShowsDisconnectAction()
```

- [ ] **Step 2: Implement section UI**

Render:

- Header: `Git Provider Accounts`
- Empty signed-in state: `Add GitHub Account...`
- Guest state: disabled prompt to sign in to macgit first.
- Connected rows with provider icon/name, username, host, token status, `Reconnect...` when needed, and `Disconnect...`.
- Loading state with disabled controls.

Actions call controller intents. The view never sees raw tokens.

- [ ] **Step 3: Route callback URLs**

In `macgitApp.swift`, extend `.onOpenURL` routing so provider auth URLs are handled before existing Google Sign-In fallback when the URL matches the provider callback scheme.

Expected behavior:

- Git provider callback is forwarded to `GitProviderAccountController`.
- Google Firebase Auth callback still goes to `GIDSignIn.sharedInstance.handle(url)`.

- [ ] **Step 4: Run targeted tests and build**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitProviderAccountsSectionTests test
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```

Expected: tests and build pass. Do not launch the app.

- [ ] **Step 5: Run the full test suite and update roadmap**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test
```

Expected: full suite passes.

Update the roadmap Phase 1 entry to `[completed]` with the branch or merge commit.

- [ ] **Step 6: Commit**

```bash
git add macgit/Services/GitProviderOAuthModels.swift macgit/Services/GitHubProviderAuthService.swift macgit/Views/Account/GitProviderAccountsSection.swift macgit/Views/Account/ManageAccountSheet.swift macgit/App/macgitApp.swift macgitTests/GitProviderOAuthTests.swift macgitTests/GitHubProviderAuthServiceTests.swift macgitTests/GitProviderAccountsSectionTests.swift docs/superpowers/plans/2026-07-06-git-provider-accounts-roadmap.md
git commit -m "feat: connect github provider accounts"
```
