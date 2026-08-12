# Commit+ Account Device Limits Phase 1: Backend Registry and Atomic Slot Enforcement

**Status:** completed locally; production deployment pending

**Implementation branch:** `codex/account-device-limits-phase-1`

## Goal

Add the server-owned device registry, atomic Free/Pro slot decisions, device-bound Firebase token minting, and security-rule primitives without changing the current macOS login UI yet.

## Prerequisites and session kickoff

- Read the [device-limit roadmap](2026-08-12-commit-account-device-limits-roadmap.md), current Firebase foundation plans, `functions/src/index.ts`, `firestore.rules`, and emulator tests.
- Confirm `/Users/thanhtran/Project/Commit+/macgit` is on a clean `main`.
- Create the branch with `git switch -c codex/account-device-limits-phase-1`.
- Confirm Firebase project/configuration and current deployed functions before any deploy. Implementation and tests do not automatically authorize a production deploy.

## Product decisions implemented here

- Free or missing/inactive entitlement -> limit 1.
- Active Pro entitlement -> limit 3.
- Only macOS app device slots are counted. Web custom-token sessions are not registered.
- The same active device ID can claim repeatedly without increasing the count.
- At the limit, the server returns a typed `device-limit-reached` result with the active-device summaries required by the recovery UI.
- Replacement atomically revokes one selected active device and activates the requesting device.
- Sign-out release is best effort and idempotent. Failure must not prevent local Firebase sign-out in Phase 2.

## Backend design

Create a focused module such as `functions/src/device-access.ts` and keep `functions/src/index.ts` as export/wiring:

- `deviceLimitForEntitlement(data)` is a pure function with exhaustive tests.
- `claimDeviceSlot(uid, device, dependencies)` runs one Firestore transaction:
  - read entitlement and device summary;
  - normalize the summary and existing current record;
  - resolve limit from server entitlement;
  - refresh an already-active device idempotently;
  - activate when capacity exists;
  - otherwise return the active-device list without writing.
- `replaceDeviceSlot(uid, replacingDeviceID, currentDevice, dependencies)` validates that the selected device is currently active, then revokes it and activates current in the same transaction.
- `releaseDeviceSlot(uid, deviceID, reason, dependencies)` removes it from the active set and marks it revoked.
- `heartbeatDevice(uid, deviceID, metadata)` updates `lastSeenAt` only for the authenticated active device and should be rate-limited by the client.
- `listAccountDevices(uid)` returns owner-safe device summaries; it never returns tokens or unrelated account data.
- `reconcileDeviceLimit(uid)` deterministically retains the active record with greatest `lastSeenAt`, breaking ties by `createdAt` then device ID, and revokes excess devices.

Expose authenticated callable functions for claim, replace, release, heartbeat, and list. Validate every field, cap string lengths, reject unknown schema versions, and ignore any client plan/limit value.

After a successful claim or replacement, mint a Firebase custom token for the same UID with:

```text
commitPlusDeviceID: <claimed random UUID>
commitPlusDeviceSessionVersion: 1
```

The claim caller must already possess a valid Firebase credential. A custom token is a one-time exchange artifact and must never be written to Firestore or logs.

## Firestore rules foundation

Add helpers and tests now, but do not deploy enforcement before Phase 2 is released:

- `signedInCommitPlusDevice(uid)` checks UID, string claim, supported session version, and an active matching device document.
- Allow the device-bound session to `get` its own device document even after it becomes revoked so a realtime listener can observe the transition.
- Deny all client writes to device summary/device documents.
- Deny cross-user reads and device collection listing through the client SDK; management uses authenticated callables.
- Prepare entitlement/settings/provider-metadata/bookmark rules to require `signedInCommitPlusDevice(uid)` behind an explicit staged rules change committed in this phase but deployed only according to Phase 3.

## Account deletion and downgrade

- Extend account deletion to remove `users/{uid}/deviceAccess/summary` and every `users/{uid}/devices/*` document. Firestore does not cascade subcollections.
- Add an entitlement document trigger that calls reconciliation whenever effective access changes.
- Repeated or out-of-order Polar/admin entitlement writes must converge to the current entitlement's limit.
- Deleting/revoking excess records must cause online device listeners and protected Firestore requests to lose access immediately.

## Expected file map

- Add `functions/src/device-access.ts`.
- Add `functions/src/device-access.test.ts` or extend `functions/src/index.test.ts` only for export-level tests.
- Modify `functions/src/index.ts` to export callable functions and entitlement reconciliation trigger.
- Modify `functions/src/index.test.ts` for expanded account-deletion coverage.
- Modify `firestore.rules` with device-bound helper/rules.
- Modify `firebase-tests/firestore.rules.test.mjs` with device claim, active/revoked, owner/cross-user, and protected-data cases.
- Modify `firebase.json` only if emulator/function trigger configuration actually requires it.

## Test plan

### Pure/function tests

- Missing/free/inactive/canceled/past-due entitlement -> 1; active Pro -> 3.
- First claim, same-device repeat, final-slot claim, and over-limit claim.
- Two simulated concurrent claims cannot produce more than the limit.
- Replacement revokes exactly the selected active ID and activates exactly the current ID.
- Replacement rejects stale, missing, cross-user, or already-revoked IDs.
- Release/heartbeat/reconcile are idempotent.
- Downgrade 3 -> 1 retains deterministic most-recent device; upgrade 1 -> 3 revokes none.
- Malformed summaries fail closed or self-repair without granting extra slots.
- Account deletion removes summary and all device documents even when the Auth user is already absent.
- Token minting receives only the claimed UID/device claims and never accepts client claims.

### Rules emulator

- Plain Firebase token cannot read protected account data after enforcement mode is applied.
- Active matching device claim can read/write its owned synced documents and read entitlement.
- Missing, wrong UID, wrong device ID, unsupported session version, and revoked device all fail.
- Current device can observe its own active-to-revoked document transition but cannot list or write devices.
- Public feature policy remains readable; client device documents remain immutable.

## Acceptance criteria

- Server transactions are the only code path that changes active slots.
- Server entitlement, not client state, selects 1 versus 3.
- Claim/replace returns a device-bound custom token only after the transaction commits.
- Concurrent requests cannot over-allocate.
- Downgrade and deletion cleanly reconcile device state.
- Rules tests prove that a revoked or unbound session cannot reach entitlement or synced Commit+ data once enforcement is deployed.
- No macOS UI behavior changes in this phase.

## Explicit non-goals

- No Swift models, Keychain identity, sheets, or controller changes.
- No production rule flip before a compatible app exists.
- No hardware attestation, fingerprint, automatic expiry, or web-device counting.
- No change to Git/provider authentication or local data.

## Verification

- Run `npm --prefix functions test`.
- Run the Firebase rules emulator test command documented by the repository.
- Run `git diff --check`.
- Run the macOS build because Functions/rules changes share the release repository: `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`.
- Do not launch the app.
- If production deploy is separately authorized, deploy Functions only at this phase and record exact deployed revisions; do not deploy the enforcing Firestore rules yet.

## Result

- Added a server-owned device registry with one transaction contention document and per-device records.
- Free/missing/inactive entitlement resolves to one slot; active Pro resolves to three.
- Claim, same-device refresh, replacement, release, heartbeat, and downgrade reconciliation are idempotent and transaction-backed.
- Successful claim/replacement mints a custom Firebase token bound to the random Commit+ device ID and session schema version.
- Callable Functions expose claim, replace, release, heartbeat, and list; an entitlement trigger reconciles Pro-to-Free excess devices.
- Account deletion removes the device subcollection and summary before deleting entitlement/Auth data.
- Firestore source now requires an active device-bound session for entitlement and synced settings/provider/bookmark metadata, while allowing the current device to observe its own revocation. These rules are intentionally not deployed until a compatible macOS release exists.
- Functions tests passed 17/17, including concurrent final-slot allocation and replacement during downgrade.
- Firestore emulator tests passed 21/21 using a temporary local JDK 21; the existing feature-policy script test was corrected to expect the already-shipped revision 4.
- `git diff --check` and the macOS build passed. The app was not launched.
