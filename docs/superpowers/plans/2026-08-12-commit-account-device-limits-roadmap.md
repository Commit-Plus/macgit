# Commit+ Account Device Limits Roadmap

**Status:** implementation completed; production rollout pending

**Goal:** Limit official Commit+ cloud sessions to one signed-in Mac for Free accounts and three for active Pro accounts, without affecting guest use or local Git.

## Final architecture

- The official macOS app generates a random UUID and stores it in the ThisDeviceOnly Keychain.
- After ordinary Firebase Authentication, the app claims its slot with a direct Firestore transaction.
- `users/{uid}/deviceAccess/summary` is the transaction contention point. The transaction reads the server-owned entitlement and permits one active ID for Free/inactive accounts or three for active Pro.
- The app observes only its own device record. If the record is revoked on the web, it stops cloud listeners, signs out, and returns to guest mode without touching local data.
- When no slot is available, the app explains the limit and opens the authenticated landing-page device section. It does not list, replace, or revoke Macs itself.
- The landing page verifies the user's Firebase ID token, then uses Firebase Admin to list or revoke devices.
- Polar entitlement changes reconcile active devices on the landing server. A downgrade retains the most recently signed-in Mac and revokes excess records.
- The existing `createWebSignInToken` Function remains only for authenticated app-to-web navigation. Device claims do not use a custom token or custom claims.

This is cooperative product enforcement for the distributed official app. Preventing a user from modifying or self-hosting the AGPL source is explicitly outside scope.

## Product contract

- The quota applies only to Firebase-authenticated Commit+ sessions in the official macOS app.
- Guest users consume no slot. Repositories, Git commands, credentials, branches, worktrees, and other machine-local data are unrelated.
- Free and inactive Pro resolve to one active Mac. Active Pro resolves to three active Macs.
- Web profile, pricing, checkout, subscription, and device management do not consume a Mac slot.
- Signing out online releases the current slot. Web removal revokes the selected slot.
- A previously verified Mac may use cached account state while offline. New sign-in and first activation require Firestore access.
- Concurrent claims are serialized by the Firestore summary transaction. This is sufficient for the current product scale; no device callable layer is required.

## Privacy boundary

- Use a cryptographically random UUID stored with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- Never use a serial number, MAC address, hardware fingerprint, Firebase Installation ID, Apple account, repository, path, or IP address as device identity.
- Store only the random ID, generic Mac family, OS/app versions, status, reason, and timestamps needed for account device management.
- Never upload repository content, paths, remotes, Git history/activity, or provider credentials as part of device access.

## Firestore data contract

```text
users/{uid}/deviceAccess/summary
  schemaVersion: 1
  activeDeviceIDs: [string]        // maximum one Free, three active Pro
  updatedAt: timestamp

users/{uid}/devices/{deviceID}
  schemaVersion: 1
  deviceID: string
  platform: macOS
  modelFamily: string
  osVersion: string
  appVersion: string
  status: active | revoked
  createdAt: timestamp
  lastSeenAt: timestamp
  revokedAt: optional timestamp
  revokedReason: optional signedOut | replaced | planDowngrade | userRevoked | accountDeleted
```

Firestore rules keep these documents owner-scoped, validate their schema and server timestamps, and cap summary IDs from the server-owned entitlement. Normal Firebase-authenticated sessions retain access to their entitlement and synced settings/provider/bookmark metadata; there are no device-bound custom claims.

## Delivery

- [completed] Random ThisDeviceOnly identity and device models.
- [completed] macOS direct Firestore claim/release/current-device observation.
- [completed] limit-reached sheet with authenticated web-management navigation and retry/cancel.
- [completed] landing Profile list/remove APIs and UI using Firebase Admin.
- [completed] Polar downgrade reconciliation.
- [completed] simplified Firestore rules and emulator coverage.
- [completed] removal of claim/replace/release/revoke/heartbeat/list/reconcile device Functions from source.
- [pending] merge both implementation branches, deploy landing, deploy Firestore rules, and delete the seven obsolete production Functions.

## Acceptance criteria

- The first Free Mac signs in; a second sees the limit screen and can open web management.
- Active Pro can sign in on three Macs; a fourth sees the same recovery path.
- Re-signing in with the same Keychain UUID is idempotent.
- Removing a Mac on the web frees its slot and signs that Mac out when its listener receives the revocation.
- Pro-to-Free reconciliation retains the most recently signed-in Mac and revokes excess Macs.
- Guest/local Git remains usable without Firebase authentication and without a device record.
- Existing authenticated web-session handoff opens `/profile?section=devices` without consuming a slot.

## Verification

- Run Functions tests and Firestore emulator rules tests.
- Run focused account/device/web-session Swift tests.
- Run the macOS build without launching the app.
- Run landing type-check and production build.
- Run `git diff --check` in both repositories.
- After deployment, fetch active Firestore source and list production Functions to verify actual state.

## Non-goals

- No DRM, attestation, hardware fingerprinting, Git-core restriction, or protection against modified/self-hosted clients.
- No device list/revoke/replace UI inside the macOS app.
- No background heartbeat, inactivity expiry, analytics, or repository telemetry.
- No deletion or remote modification of local repositories, settings, credentials, or Git data.

