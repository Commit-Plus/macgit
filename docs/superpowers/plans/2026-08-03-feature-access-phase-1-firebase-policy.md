# Feature Access Phase 1: Firebase Policy Foundation

**Branch:** `codex/feature-access-phase-1`

## Goal

Add a typed, testable feature-policy boundary that can receive a global release policy from Firestore without changing current feature behavior yet.

## Tasks

- [completed] Define stable feature identifiers, plan rules, repository scopes, and bundled defaults matching the landing-page pricing matrix.
- [completed] Add strict Firestore decoding, realtime observation, local caching, and fallback behavior.
- [completed] Add a shared access resolver and app-owned controller outside SwiftUI views.
- [completed] Allow public reads and deny client writes for `featurePolicies/release` with emulator coverage.
- [completed] Add an operator script that publishes the bundled release policy shape.
- [completed] Add focused Swift tests, run `git diff --check`, and build the macOS app without launching it.

## Acceptance criteria

- Free denies hosted private repositories and AI features.
- Free allows Pull Request on public repositories and Git Flow on public or local-only repositories.
- Active Pro allows public and private repositories for the scoped release features.
- Inactive, canceled, or malformed Pro entitlement resolves as Free.
- A malformed remote feature entry cannot grant access and falls back to the bundled entry.
- An unavailable Firestore listener retains the last valid cached or in-memory policy.
- Firebase clients can read the release policy but cannot create, update, or delete it.
- Phase 1 does not yet hide or block existing app actions.
