# Commit+ Account Device Limits Roadmap

**Goal:** Limit signed-in Commit+ macOS devices to one for Free accounts and three for active Pro accounts while keeping guest/local Git use unchanged.

**Architecture:** Each Commit+ installation owns a random device identifier stored only in this Mac's Keychain. After ordinary Firebase authentication, a callable backend atomically claims a device slot from the user's server-owned registry and exchanges the temporary Firebase session for a device-bound Firebase session. Firestore permits account entitlement and Commit+ sync data only while that device record remains active. SwiftUI renders controller state and recovery choices; it never calculates or mutates quota directly.

## Product contract

- The quota applies only to Firebase-authenticated Commit+ sessions in the macOS app.
- Guest users do not consume a slot. Local repositories, local Git state, and every guest Git operation are outside this roadmap.
- Free and inactive/canceled Pro resolve to one active Mac. Active Pro resolves to three active Macs.
- Web sign-in for the Commit+ profile, pricing, checkout, or subscription management does not consume a Mac slot.
- A slot persists until the user signs out online, revokes/replaces that Mac, deletes the account, or a plan downgrade removes excess slots. There is no inactivity expiry in this version.
- When a Pro account with multiple active Macs becomes Free, retain the most recently verified Mac and revoke the others.
- A device-limit denial must not leave the app in an authenticated Commit+ state. The temporary Firebase credential may remain only long enough to let the user replace an existing Mac, retry after upgrading, or cancel.
- A previously activated Mac may retain its last verified account and entitlement while offline. New sign-in, first migration, replacement, and revocation confirmation require the network. Server rules remain authoritative when connectivity returns.
- Revoking a Mac takes effect for entitlement and sync on its next online request/listener update; offline local work cannot be remotely disabled.

## Privacy and identity boundary

- Generate a cryptographically random UUID; store it with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- Never derive identity from a serial number, MAC address, Firebase Installation ID, Apple account, repository, path, IP address, or hardware fingerprint.
- The server may store only the random ID, generic model family, OS/app versions, status, reason, and created/last-seen/revoked timestamps needed for device management.
- Do not upload repository names, remotes, paths, Git activity, or provider credentials as part of device access.
- Update the public privacy copy before enforcement because the current site incorrectly says that Commit+ has no accounts or device identifiers.

## Server-owned data contract

```text
users/{uid}/deviceAccess/summary
  schemaVersion: 1
  activeDeviceIDs: [string]        // maximum three
  updatedAt: timestamp

users/{uid}/devices/{deviceID}
  schemaVersion: 1
  status: active | revoked
  platform: macOS
  modelFamily: string              // generic, e.g. MacBook Pro
  osVersion: string
  appVersion: string
  createdAt: timestamp
  lastSeenAt: timestamp
  revokedAt: optional timestamp
  revokedReason: optional signedOut | replaced | planDowngrade | userRevoked | accountDeleted
```

- Only Admin SDK code may create, activate, revoke, or delete these records.
- `activeDeviceIDs` is the transaction contention point and authoritative active set; device documents provide display and revocation state.
- The backend derives the limit from the current server-owned entitlement inside the transaction. It never trusts a client-provided plan or limit.
- Device-bound Firebase tokens include `commitPlusDeviceID` and `commitPlusDeviceSessionVersion`. Firestore rules require the claim to match an active device document.

## Phases

- [completed] [Phase 1: Backend registry and atomic slot enforcement](2026-08-12-commit-account-device-limits-phase-1-backend.md) (branch: `codex/account-device-limits-phase-1`; production deployment pending)
- [completed] [Phase 2: macOS session activation and limit recovery UX](2026-08-12-commit-account-device-limits-phase-2-macos.md) (branch: `codex/account-device-limits-phase-2`; release pending)
- [in progress] [Phase 3: Device management, downgrade, privacy, and production rollout](2026-08-12-commit-account-device-limits-phase-3-rollout.md) (implementation complete; release/deployment pending)

## Recommended order

1. Deploy Phase 1 callable functions without tightening Firestore rules.
2. Ship the Phase 2-compatible macOS build so official clients can obtain device-bound sessions.
3. Complete Phase 3 management/downgrade behavior and privacy copy.
4. After the compatible build is available, deploy enforcement rules and verify active production source. Older builds may continue local Git but must update before account entitlement or sync works again.

## Shared implementation rules

- Start every phase from a clean `main` and use its specified `codex/` branch. Do not implement phase work directly on `main`.
- Keep Firebase imports inside services. `AccountSessionController` coordinates state; SwiftUI views only render state and send intents.
- The backend is the sole quota authority. Client checks are presentation/preflight only.
- Claim, replacement, release, heartbeat, downgrade reconciliation, and account deletion must be idempotent.
- Concurrent claims must never create more than the resolved limit.
- Do not sign a user out for a transient network error. Sign out only after a definitive revocation/limit result or explicit user intent.
- Reset visible entitlement to Free and stop every cloud listener when device access is definitively revoked.
- Apply active-device rules to Commit+ entitlement and synced account data: app settings, provider-account metadata, and repository bookmarks. Public release feature policy remains public.
- Preserve local-first behavior: a failed sync or revoked account session never rolls back settings already applied locally and never deletes local provider credentials/bookmarks/repositories.
- Every new Swift file starts with the required AGPL v3 header.

## Roadmap-level acceptance criteria

- The first Free Mac signs in; a second Free Mac receives a device-limit recovery screen instead of an authenticated app session.
- Active Pro can have three Macs; a fourth must replace/revoke one or cancel.
- Two concurrent final-slot claims result in exactly one activation.
- Re-signing in from the same device ID is idempotent and does not consume another slot.
- Reinstalling while the ThisDeviceOnly Keychain item survives reuses the same slot. A cleared Keychain is treated as a new Mac and can replace the stale slot.
- Revocation stops entitlement observation and all Commit+ cloud sync for that Mac when online, then returns the app to guest state without touching local Git.
- Offline use works only from a previously verified device cache; an unverified device cannot create a slot or obtain fresh Pro/cloud data offline.
- Pro-to-Free downgrade leaves one most-recently-verified Mac active and signs the others out when they reconnect.
- Account deletion removes the device summary and every device document as well as current settings/entitlement data.
- Web profile/pricing sessions do not consume slots.

## Explicit non-goals

- No DRM, binary attestation, hardware fingerprinting, or prevention of source-code modification/self-hosting.
- No restriction on guest/local Git, repositories, branches, worktrees, credentials, Git runtime, or provider transport.
- No device quota for GitHub/GitLab OAuth device flow; that is unrelated provider authentication.
- No iOS, Windows, Linux, Team seat licensing, organization administration, or shared-device policy.
- No automatic stale-device expiry or background usage analytics.
- No remote deletion of local settings, repositories, provider tokens, or Git data.

## Final verification

- Run focused Cloud Functions tests and Firebase emulator/rules tests.
- Run focused Swift model/service/controller/presentation tests.
- Run `git diff --check`.
- Run `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build` without launching the app.
- If the Firebase XCTest host aborts during bootstrapping, do not rerun the same command; retain the focused evidence and successful build.
- Verify the deployed Functions revisions and fetch the active Firestore rules source after rollout; CLI success alone is not sufficient.
