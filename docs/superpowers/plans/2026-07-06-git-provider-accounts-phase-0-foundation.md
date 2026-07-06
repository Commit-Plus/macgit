# Git Provider Accounts Phase 0 Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the provider account model, Keychain token-vault boundary, metadata-store boundary, and controller state without integrating a real provider.

**Architecture:** `GitProviderAccountController` belongs to the signed-in macgit user but is separate from `AccountSessionController`. Provider metadata is app-owned data; provider tokens are available only through `GitProviderTokenVault`.

**Tech Stack:** Swift, SwiftUI state models, Security Keychain Services, Cloud Firestore protocol boundary, XCTest, `xcodebuild`.

---

## File Structure

- Create `macgit/Models/GitProviderAccountModels.swift`: provider account, host, token, permission, and repository identity models.
- Create `macgit/Services/GitProviderTokenVault.swift`: token vault protocol and Keychain implementation.
- Create `macgit/Services/GitProviderAccountStore.swift`: metadata-store protocol and in-memory test implementation; Firestore implementation is added only if Firebase dependencies are available in the phase branch.
- Create `macgit/App/GitProviderAccountController.swift`: observable provider-account session state scoped to the current macgit UID.
- Create `macgitTests/GitProviderAccountModelsTests.swift`: model encoding and host normalization tests.
- Create `macgitTests/GitProviderTokenVaultTests.swift`: token-vault behavior using an in-memory fake plus Keychain wrapper unit coverage where practical.
- Create `macgitTests/GitProviderAccountControllerTests.swift`: account loading, disconnect, and device-token status tests.

### Task 1: Add Provider Account Models

**Files:**
- Create: `macgit/Models/GitProviderAccountModels.swift`
- Test: `macgitTests/GitProviderAccountModelsTests.swift`

- [x] **Step 1: Write model tests**

Add tests for:

```swift
func testGitHubDotComHostNormalizesToHttpsBaseURL()
func testSelfHostedGitLabHostPreservesHost()
func testProviderAccountRoundTripsCodable()
func testUnavailableTokenStatusIsDistinctFromRevoked()
```

Expected assertions:

- `GitProviderHost.githubDotCom.baseURL.absoluteString == "https://github.com"`
- `GitProviderHost(kind: .gitlab, baseURL: URL(string: "https://git.company.com/")!).normalized.baseURL.absoluteString == "https://git.company.com"`
- Codable round-trip preserves `providerUserID`, `username`, `scopes`, `permissions`, and `tokenStatus`.
- `.unavailableOnThisDevice != .revoked`.

- [x] **Step 2: Run the model test and confirm missing-type failure**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitProviderAccountModelsTests test
```

Expected: compile fails because `GitProviderAccount` and related types do not exist.

- [x] **Step 3: Implement the models**

Create:

```swift
enum GitProviderKind: String, Codable, CaseIterable, Identifiable {
    case github
    case gitlab

    var id: String { rawValue }
}

struct GitProviderHost: Hashable, Codable {
    var kind: GitProviderKind
    var baseURL: URL

    static let githubDotCom = GitProviderHost(kind: .github, baseURL: URL(string: "https://github.com")!)

    var normalized: GitProviderHost {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.scheme = components?.scheme ?? "https"
        components?.path = ""
        components?.query = nil
        components?.fragment = nil
        return GitProviderHost(kind: kind, baseURL: components?.url ?? baseURL)
    }
}

enum GitProviderTokenStatus: String, Codable, Equatable {
    case valid
    case expired
    case revoked
    case reauthorizationRequired
    case unavailableOnThisDevice
}

struct GitProviderAccount: Identifiable, Equatable, Codable {
    var id: String
    var macgitUID: String
    var provider: GitProviderKind
    var hostURL: URL
    var providerUserID: String
    var username: String
    var displayName: String?
    var avatarURL: URL?
    var scopes: [String]
    var permissions: [String: String]
    var tokenStatus: GitProviderTokenStatus
    var connectedAt: Date
    var lastValidatedAt: Date?
}

struct GitProviderToken: Equatable, Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var tokenType: String
}

struct GitRepositoryIdentity: Equatable, Codable {
    var provider: GitProviderKind
    var hostURL: URL
    var owner: String
    var name: String
}
```

- [x] **Step 4: Run the model tests**

Run the same focused test command.

Expected: all model tests pass.

- [x] **Step 5: Commit**

```bash
git add macgit/Models/GitProviderAccountModels.swift macgitTests/GitProviderAccountModelsTests.swift
git commit -m "feat: add git provider account models"
```

### Task 2: Add Token Vault Boundary

**Files:**
- Create: `macgit/Services/GitProviderTokenVault.swift`
- Test: `macgitTests/GitProviderTokenVaultTests.swift`

- [x] **Step 1: Write vault tests**

Cover these behaviors:

```swift
func testInMemoryVaultSavesReadsAndDeletesToken()
func testKeychainAccountKeyIncludesMacgitUIDProviderHostAndProviderUserID()
func testMissingTokenReturnsNil()
```

- [x] **Step 2: Implement the vault protocol and account key helper**

Add:

```swift
protocol GitProviderTokenVault {
    func readToken(for account: GitProviderAccount) throws -> GitProviderToken?
    func saveToken(_ token: GitProviderToken, for account: GitProviderAccount) throws
    func deleteToken(for account: GitProviderAccount) throws
}

enum GitProviderTokenVaultKey {
    static func key(for account: GitProviderAccount) -> String {
        let host = account.hostURL.host(percentEncoded: false) ?? account.hostURL.absoluteString
        return [account.macgitUID, account.provider.rawValue, host.lowercased(), account.providerUserID].joined(separator: ":")
    }
}
```

- [x] **Step 3: Implement the Keychain vault**

Use Security framework calls:

- `SecItemCopyMatching` for read.
- `SecItemAdd` for first save.
- `SecItemUpdate` when save finds `errSecDuplicateItem`.
- `SecItemDelete` for deletion.

Use:

- `kSecClassGenericPassword`
- `kSecAttrService = "com.commitplus.macgit.git-provider-tokens"`
- `kSecAttrAccount = GitProviderTokenVaultKey.key(for:)`
- `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`

- [x] **Step 4: Run focused vault tests**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitProviderTokenVaultTests test
```

Expected: tests pass without touching real provider networks.

- [x] **Step 5: Commit**

```bash
git add macgit/Services/GitProviderTokenVault.swift macgitTests/GitProviderTokenVaultTests.swift
git commit -m "feat: add git provider token vault"
```

### Task 3: Add Metadata Store and Controller

**Files:**
- Create: `macgit/Services/GitProviderAccountStore.swift`
- Create: `macgit/App/GitProviderAccountController.swift`
- Test: `macgitTests/GitProviderAccountControllerTests.swift`

- [x] **Step 1: Write controller tests**

Cover:

```swift
func testSignedOutStateDoesNotLoadProviderAccounts()
func testSignedInStateLoadsAccountsForCurrentMacgitUID()
func testAccountWithoutLocalTokenIsMarkedUnavailableOnThisDevice()
func testDisconnectDeletesLocalTokenBeforeMetadata()
```

- [x] **Step 2: Add metadata-store protocol**

Add:

```swift
protocol GitProviderAccountStore {
    func accounts(forMacgitUID uid: String) async throws -> [GitProviderAccount]
    func save(_ account: GitProviderAccount) async throws
    func delete(accountID: String, macgitUID: String) async throws
}
```

Include an in-memory fake inside tests for deterministic behavior.

- [x] **Step 3: Add controller**

Implement `@MainActor final class GitProviderAccountController: ObservableObject` with:

- `@Published private(set) var accounts: [GitProviderAccount] = []`
- `@Published private(set) var isLoading = false`
- `@Published var errorMessage: String?`
- `func updateMacgitAccount(_ account: AccountSnapshot?) async`
- `func reload() async`
- `func disconnect(_ account: GitProviderAccount) async`

When loading accounts, call the token vault for each metadata record. If token read returns nil, publish the account with `.unavailableOnThisDevice`.

- [x] **Step 4: Run focused controller tests**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitProviderAccountControllerTests test
```

Expected: controller tests pass.

- [x] **Step 5: Run the full test suite**

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test
```

Expected: full suite passes.

- [x] **Step 6: Update roadmap and commit**

Update `docs/superpowers/plans/2026-07-06-git-provider-accounts-roadmap.md` Phase 0 to `[completed]` with the branch or merge commit.

```bash
git add macgit/Services/GitProviderAccountStore.swift macgit/App/GitProviderAccountController.swift macgitTests/GitProviderAccountControllerTests.swift docs/superpowers/plans/2026-07-06-git-provider-accounts-roadmap.md
git commit -m "feat: add git provider account controller"
```
