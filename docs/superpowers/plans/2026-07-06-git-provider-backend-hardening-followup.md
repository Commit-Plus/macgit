# Git Provider Backend Hardening Follow-Up

**Date:** 2026-07-08
**Status:** Follow-up plan
**Scope:** Backend-only provider flows that should not run in the macOS client because they require confidential server-owned secrets, webhook receivers, organization policy, or cross-device token custody.

## Client-Only Baseline

The current Git provider roadmap remains usable without backend deployment:

- Firebase Auth remains the Commit+ identity.
- GitHub and GitLab provider accounts are separate connected accounts.
- Provider access tokens are stored only in the local macOS Keychain.
- Private HTTPS Git operations use environment-based askpass credential injection.
- Pull request and merge request read/write actions use the connected local provider token.

## Backend Triggers

Move a provider flow to Firebase Functions or Cloud Run when one of these is required:

- **GitHub App installation-token minting:** mint short-lived installation tokens only on a trusted backend after verifying the signed-in Commit+ user and the selected installation/repository access.
- **GitHub App private key custody:** keep the GitHub App private key out of the macOS app bundle, local preferences, Firestore, logs, crash reports, and command-line arguments.
- **Provider webhooks:** receive GitHub/GitLab webhook events on a backend endpoint that verifies provider signatures, deduplicates delivery IDs, and writes only non-secret derived state.
- **Org/team policy enforcement:** evaluate organization membership, team membership, repository allowlists, enterprise policy, or subscription constraints server-side before returning an authorization decision.
- **Cross-device provider token sync:** store or broker usable provider credentials only if encrypted, auditable, revocable, and explicitly scoped to the signed-in Commit+ user.
- **Server-side token refresh rotation:** rotate refresh tokens from a trusted backend when the provider requires confidential client authentication or stronger audit controls than a local client can provide.

## Deployment Note

Deploying Firebase Functions or Cloud Run requires Firebase Blaze billing. The client-only roadmap does not require Blaze billing and should continue to work for local Keychain-backed provider accounts when no backend-only trigger applies.

## Non-Goals

- Do not store provider access tokens, refresh tokens, GitHub App private keys, or client secrets in Firestore.
- Do not make Firebase Auth provider linkage a substitute for Git provider accounts.
- Do not proxy ordinary local Git operations through the backend.
