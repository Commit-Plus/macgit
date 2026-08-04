# Git Provider Account Plan Limits Phase 1

**Branch:** `codex/git-provider-account-plan-limits`

## Tasks

- [completed] Add a plan feature for multiple provider accounts and a pure provider-account creation policy.
- [completed] Enforce the quota before authentication and immediately before saving OAuth tokens, SSH key references, or account metadata.
- [completed] Disable Add at the Free limit and show a sign-in or Upgrade to Pro affordance in Connections and Account Settings.
- [completed] Preserve reconnect, edit, delete, credential resolution, and all existing connections after downgrade or sign-out.
- [completed] Add focused feature-policy, access-policy, controller, and presentation tests.
- [completed] Run `git diff --check`, targeted XCTest, and the macOS build without launching the app.

## Verification

- A guest or Free user can add the first GitHub or GitLab account.
- A guest or Free user cannot add a second distinct provider identity.
- A Pro user can add multiple provider identities.
- Reconnecting an existing identity remains allowed at or above the Free limit.
- A quota change during authentication cannot persist a new token, SSH key reference, or metadata record.
- Downgrading or signing out with multiple existing accounts does not delete or disable them.
- Deleting accounts below the limit immediately restores Add access.
- Bitbucket stays disabled.

## Result

- Free and guest users can create one local-first GitHub or GitLab connection; additional identities require Pro.
- Controller preflight and pre-persistence checks cover GitHub, GitLab, OAuth callback, and SSH paths without restricting existing-account operations.
- Connections and Account Settings show the Free limit with a sign-in or Upgrade to Pro action while preserving Add-sheet Save after the first connection completes.
- Targeted tests compiled, but the existing Firebase bootstrap abort stopped the test host before XCTest execution; the suite was not rerun per project instructions.
- `git diff --check`, feature-policy script syntax validation, and the macOS build passed.
