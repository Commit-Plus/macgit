# Feature Access Roadmap

## Goal

Make Commit+ plan boundaries centrally configurable from Firebase while keeping entitlement, repository visibility, and feature policy as separate inputs.

## Phases

- [completed] [Phase 1: Firebase policy foundation](2026-08-03-feature-access-phase-1-firebase-policy.md)
- [completed] [Phase 2: Repository visibility and private-repository access](2026-08-04-feature-access-phase-2-repository-visibility.md)
- [completed] [Phase 3: Private collaboration gates and reusable Pro upgrade UI](2026-08-04-feature-access-phase-3-enforcement.md) (branch: `codex/feature-access-phase-3`; private Pull Requests are gated while core Git remains available)
- [pending] Phase 4: AI feature gates and server-enforced cloud quotas

## Shared constraints

- Free can open and clone public, private, and local-only repositories. Selected advanced actions inside hosted private repositories require active Pro access.
- There is no one-private-repository quota or repository activation ledger.
- Entitlements remain UID-scoped and server-controlled at `entitlements/{uid}`.
- Global policy is read from `featurePolicies/release`, cached locally, and validated before use.
- A missing, malformed, or unavailable remote policy falls back to the last valid cache and then the bundled release policy.
- Feature policy never stores repository paths, remotes, credentials, source code, or other local Git data.
- UI, menu, toolbar, keyboard, and service entry points must resolve access through the same policy boundary.
- Cloud AI and usage quotas must be enforced again on the server; macOS gating alone is not a security boundary.
