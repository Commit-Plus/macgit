# Bitbucket Provider Roadmap

**Goal:** Add Bitbucket Cloud as a first-class Git provider without weakening Commit+'s local-first credential boundary.

**Architecture:** Bitbucket account metadata follows the existing `GitProviderAccount` store, while API tokens remain local in Keychain and SSH key references remain local on the Mac. Git HTTPS operations receive credentials only through the temporary askpass injector.

## Plan Index

- Phase 1: [completed] [Bitbucket Git credentials](2026-08-14-bitbucket-provider-phase-1-git-credentials.md) (branch: `codex/bitbucket-provider-git-credentials`)
- Phase 2: [pending] Bitbucket pull request read and actions

## Shared Rules

- Use Bitbucket Cloud API tokens with `read:repository:bitbucket` and `write:repository:bitbucket` for HTTPS Git operations.
- Never store API tokens in Firestore, UserDefaults, repository files, remote URLs, logs, or command arguments.
- Keep provider tokens in Keychain through `GitProviderTokenVault`.
- Keep SSH private keys and passphrases outside Commit+; store only the selected local key path.
- Keep guest/local Git flows available without a Commit+ account.
- Treat Bitbucket PR API support as a separate phase from Git transport credentials.

## Completion

The roadmap is complete when Bitbucket Cloud supports connected-account Git credentials and the same core pull request workflows currently available for GitHub and GitLab.
