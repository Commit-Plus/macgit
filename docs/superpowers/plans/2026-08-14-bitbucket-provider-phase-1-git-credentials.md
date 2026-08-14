# Bitbucket Provider Phase 1: Git Credentials

**Status:** [completed]

**Goal:** Allow users to connect a Bitbucket Cloud account with an API token or SSH key and use it for push, pull, and fetch.

## Scope

- Add Bitbucket to `GitProviderKind` and remote identity resolution.
- Add `bitbucket.org` as a normalized provider host.
- Add a manual API-token connection flow that validates required input and stores the token in Keychain.
- Reuse the existing SSH authentication and local key-reference flow for Bitbucket.
- Route Bitbucket HTTPS and SSH remotes through the existing credential resolver and injectors.
- Permit Bitbucket provider metadata in Firestore rules.
- Update Account Settings copy and provider presentation policy.
- Add focused model, resolver, controller, presentation-policy, and rules coverage.

## Out of Scope

- Bitbucket OAuth.
- Bitbucket pull request API reads, comments, approvals, merges, or creation.
- Bitbucket Server/Data Center and self-hosted instances.
- App passwords, which Bitbucket Cloud has replaced with API tokens.

## Verification

- Run focused provider, remote identity, controller, presentation-policy, and Firestore rules tests.
- Run `git diff --check`.
- Build the macOS app without launching it.
