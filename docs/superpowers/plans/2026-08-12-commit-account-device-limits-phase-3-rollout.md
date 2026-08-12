# Commit+ Account Device Limits Phase 3: Web Management and Simplified Rollout

**Status:** implementation and Firebase rollout completed; landing deployment and macOS release pending

## Architecture revision

The original Phase 3 plan placed device management in the macOS app and relied on seven callable/trigger Functions plus device-bound custom claims. That design was intentionally replaced before the Firestore rules rollout.

The final implementation keeps only the existing app-to-web custom-token Function. The official app claims/releases through Firestore, shows a recovery sheet when full, and opens `/profile?section=devices`. The landing page owns list/revoke UI and uses Firebase Admin. Polar webhook handling reconciles downgrades.

## Implemented scope

### macOS/Firebase repository

- Direct transactional claim/release service using Firebase Auth and Firestore.
- Current-device listener for web revocation.
- Limit sheet with Manage Devices on Web, Try Again, Cancel, and Pro pricing recovery.
- No in-app list, replace, revoke, or heartbeat behavior.
- Rules validate owner access, schemas, server timestamps, and entitlement-derived summary limits.
- The seven device-specific Function exports and their implementation/tests are removed.
- Account deletion still clears device documents and summary.

### landing-page repository

- Authenticated `GET /api/devices` and `DELETE /api/devices/[deviceID]` routes.
- Signed-in Macs section on Profile with count, refresh, and confirmed removal.
- App web-session allowlist supports `/profile?section=devices`.
- Polar subscription updates reconcile the active-device set to three or one.

## Production rollout

1. [completed] Merge both implementation branches to their local `main` branches.
2. [pending] Deploy the landing page so web management exists before an official app release relies on it.
3. [completed] Deploy the simplified Firestore rules and verify the active source.
4. [completed] Delete the obsolete production Functions:
   - `claimCommitPlusDevice`
   - `replaceCommitPlusDevice`
   - `releaseCommitPlusDevice`
   - `revokeCommitPlusDevice`
   - `heartbeatCommitPlusDevice`
   - `listCommitPlusDevices`
   - `reconcileCommitPlusDeviceLimit`
5. [completed] Confirm `createWebSignInToken` and `deleteAccount` remain deployed.
6. [pending] Release the compatible macOS build and exercise live Free/Pro limits plus web revocation.

## Verification record

- Functions source tests: four retained tests pass after stale generated device tests are removed.
- Firestore emulator: rules tests cover ordinary Firebase sessions, owner isolation, Free one-slot, Pro three-slot, and device schema validation.
- macOS: focused account/device/web-session tests and build must pass; do not launch the app.
- landing: TypeScript and production Next.js build must pass.
- Runtime multi-Mac behavior and deployed landing UI remain explicit production smoke tests.
- Production Firestore ruleset `026984a8-4101-41e4-a169-7f0614588620` matched the local source after deployment.
- The production Functions inventory contains only `createWebSignInToken` and `deleteAccount` after cleanup.

## Non-goals

- No Git-core or local Git limitation.
- No device management UI in macOS.
- No server callable for routine device claim/release.
- No hard enforcement against a user-modified or self-hosted AGPL build.
