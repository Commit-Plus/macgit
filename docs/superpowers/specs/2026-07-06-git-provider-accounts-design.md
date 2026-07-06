# Git Provider Accounts Design

**Date:** 2026-07-06
**Status:** Draft roadmap source
**Scope:** Connected Git provider accounts for GitHub first, GitLab-compatible architecture second, private repository access, and pull request workflows.

## Overview

Commit+ already has a Firebase-backed macgit account. That account is the app identity: settings sync, entitlement, subscription state, and future cloud-owned app data.

GitHub, GitLab, Bitbucket, self-hosted GitLab, and future providers are not macgit identities. They are connected Git provider accounts owned by the signed-in macgit user. A single macgit user can connect multiple provider accounts, including multiple GitHub identities and self-hosted provider hosts.

The feature must let a user authenticate a provider account, use private repositories from that provider, and interact with pull requests without changing the guest-first local Git experience.

## Product Decisions

- Firebase Auth remains the only macgit account system.
- Git provider credentials are never linked into Firebase Auth provider data.
- A macgit account can have zero, one, or many provider accounts.
- Local Git continues to work without signing in to macgit or connecting a provider.
- Provider features that require identity are disabled with a clear connected-account prompt.
- Provider tokens are stored only in macOS Keychain in the first implementation.
- Firestore may store non-secret provider metadata for the signed-in macgit user.
- Firestore must never store provider access tokens, refresh tokens, client secrets, private keys, or installation tokens.
- GitHub is the first real provider implementation.
- GitLab support uses the same provider account and token-vault boundaries, with provider-specific OAuth and API clients.
- Manual personal access token import is a fallback for self-hosted or unsupported providers, not the default GitHub path.
- GitHub App authorization is preferred for long-term GitHub integration because permissions are granular and repository-scoped.
- OAuth authorization-code with PKCE is acceptable for native-client MVP flows when no provider app private key is needed.
- Backend work is deferred until a provider requires confidential server-owned secrets, webhooks, installation-token minting, org policy enforcement, or cross-device token sync.

## Goals

- Model connected provider accounts separately from `AccountSnapshot`.
- Provide Account settings UI for adding, listing, refreshing, and removing provider accounts.
- Store provider tokens in Keychain through a small vault protocol.
- Store non-secret provider connection metadata under the macgit user.
- Authenticate GitHub using an external browser and a verified callback flow.
- Use provider credentials for HTTPS private repository Git operations without logging secrets.
- Add a pull request service that can list PRs for a repository and create PRs from local branches.
- Keep provider code behind app-owned protocols so GitHub and GitLab can coexist without UI rewrites.

## Non-Goals

- Replacing Firebase Auth with GitHub or GitLab login.
- Storing provider tokens in Firestore.
- Syncing usable provider tokens across devices.
- Shipping a GitHub App private key inside the macOS app.
- Hosting webhooks in the macOS app.
- Implementing every GitHub review feature in the first PR phase.
- Implementing Bitbucket, Gitea, Azure DevOps, or Gerrit in this roadmap.
- Rewriting existing local Git operations that do not require provider authentication.

## Account Model

### macgit Account

Owned by existing Firebase code:

```swift
struct AccountSnapshot: Equatable {
    let uid: String
    let email: String?
    let displayName: String?
    let providerIDs: [String]
}
```

This identity answers "who is using Commit+?"

### Git Provider Account

New app-owned model:

```swift
enum GitProviderKind: String, Codable, CaseIterable {
    case github
    case gitlab
}

struct GitProviderHost: Hashable, Codable {
    var kind: GitProviderKind
    var baseURL: URL
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

enum GitProviderTokenStatus: String, Codable {
    case valid
    case expired
    case revoked
    case reauthorizationRequired
    case unavailableOnThisDevice
}
```

This identity answers "which Git service account can Commit+ use for this operation?"

## Local Secret Storage

Provider credentials are stored through:

```swift
protocol GitProviderTokenVault {
    func readToken(for accountID: String) throws -> GitProviderToken?
    func saveToken(_ token: GitProviderToken, for accountID: String) throws
    func deleteToken(for accountID: String) throws
}

struct GitProviderToken: Equatable, Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var tokenType: String
}
```

The production implementation uses Keychain:

- Service: `com.commitplus.macgit.git-provider-tokens`
- Account key: `<firebaseUID>:<provider>:<normalizedHost>:<providerUserID>`
- Accessibility: available after first unlock, current device only.
- Token payload: encoded JSON data.

Tests use an in-memory vault.

## Firestore Metadata

Optional non-secret metadata lives under the existing macgit user:

```text
users/{uid}/gitProviderAccounts/{connectionID}
  schemaVersion: 1
  provider: github | gitlab
  hostURL: string
  providerUserID: string
  username: string
  displayName: string?
  avatarURL: string?
  scopes: string[]
  permissions: map<string,string>
  tokenStatus: valid | expired | revoked | reauthorizationRequired | unavailableOnThisDevice
  connectedAt: timestamp
  lastValidatedAt: timestamp?
```

The document is useful for UI continuity and account audit. A second device can show that an account exists but must connect its own local token before using private repos or PR actions.

## OAuth and Provider Auth

All interactive provider auth uses the system browser, not an embedded web view.

The client must:

- Generate a random `state`.
- Generate a PKCE verifier and `S256` challenge when the provider supports PKCE.
- Open the provider authorization URL in the default browser.
- Receive a callback through a registered custom URL scheme or loopback callback.
- Verify the callback `state`.
- Exchange the authorization code through the selected provider auth client.
- Fetch the provider user profile before saving metadata.
- Save tokens to Keychain before writing a connected metadata record.

GitHub implementation choices:

- Prefer GitHub App user authorization for granular account/repository permissions.
- Use OAuth App authorization-code with PKCE only when the selected GitHub configuration does not require a confidential secret.
- Do not ship a GitHub App private key or OAuth client secret in the app bundle.

GitLab implementation choices:

- Use OAuth authorization-code with PKCE for GitLab.com and self-hosted GitLab when available.
- Let self-hosted configuration provide a host URL and app client ID.
- Treat host trust and callback URL setup as explicit user/admin configuration.

## Private Repository Git Operations

Private repository Git access uses the existing `Process()`-based Git execution path. Tokens must not be placed in remote URLs, command-line arguments, or logs.

Add a credential injection layer that can provide HTTPS credentials to Git through environment-only helpers:

```text
GIT_TERMINAL_PROMPT=0
GIT_ASKPASS=<temporary helper path>
```

The helper returns a username for username prompts and an access token for password prompts. The helper file is created with restrictive permissions, removed after the Git command, and never logs the token.

Provider account selection for a remote is based on:

1. Parsed remote host and owner/repository.
2. A repository-specific saved provider account choice when present.
3. A single matching connected account for that host.
4. A prompt when multiple accounts can access the same host.

## Pull Request Workflows

The first PR surface should support:

- Detect provider and repository from the selected repository remote.
- List open PRs for the current repository.
- Open a PR in the browser.
- Create a PR from a local branch to a target branch.
- Checkout a PR branch when the provider exposes a fetch ref.
- Show clear auth errors when the connected account is missing, expired, revoked, or lacks repository permission.

Provider API clients stay behind:

```swift
protocol PullRequestProviding {
    func listPullRequests(repository: GitRepositoryIdentity, accountID: String) async throws -> [PullRequestSummary]
    func createPullRequest(_ draft: PullRequestDraft, accountID: String) async throws -> PullRequestSummary
}
```

## Security Rules

- Provider tokens are secrets and must not be logged.
- Provider tokens are not Firestore data.
- Provider tokens are not command-line arguments.
- Provider auth callbacks must verify `state`.
- OAuth flows must use PKCE whenever the selected provider flow supports it.
- Keychain deletion must happen before metadata deletion is considered complete locally.
- Removing a provider account must never delete the macgit Firebase user.
- Deleting the macgit account must remove provider metadata and local Keychain entries for that macgit UID, but it must not revoke provider accounts automatically unless the user explicitly chooses revoke.
- If a token refresh fails, mark the provider account as `reauthorizationRequired` and keep metadata for reconnect.

## External References Checked

- GitHub OAuth authorization and device flow docs: https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps
- GitHub Apps versus OAuth Apps docs: https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/differences-between-github-apps-and-oauth-apps
- GitHub PKCE changelog: https://github.blog/changelog/2025-07-14-pkce-support-for-oauth-and-github-app-authentication/
- GitLab OAuth provider docs: https://docs.gitlab.com/integration/oauth_provider/
