# Commit+ Account Device Limits Phase 3: Management, Downgrade, Privacy, and Production Rollout

**Status:** implementation completed locally; release and production rollout pending

**Implementation branches:**

- macOS/Firebase repository: `codex/account-device-limits-phase-3`
- landing-page repository, if changed separately: `codex/account-device-limits-policy`

## Goal

Complete self-service device management, downgrade/revocation UX, account cleanup, public disclosures, and a staged production rollout that makes the one/three-device contract enforceable for Commit+ entitlement and sync.

## Prerequisites and session kickoff

- Phases 1 and 2 must be merged to `main`; Phase 1 Functions must be deployed and a Phase 2-compatible app build must be available before rules enforcement.
- Read the roadmap, prior phase plans/results, current production Functions revisions, active Firestore rules source, Polar entitlement writer, pricing/profile pages, and privacy policy.
- Start each affected repository from clean `main` and create the branch listed above.
- Do not infer authorization to deploy. Code, release, Functions deploy, and Firestore rules deploy are separately reportable operations.

## Manage Devices UX

Extend Manage Account with a `Devices` row showing `1 of 1` or `2 of 3` and a `Manage Devices...` sheet:

- List active Macs first, then optionally the current session's freshly revoked status long enough to explain it.
- Show generic model family, current-device label, app/OS version, first linked, and last active.
- Allow revoking another Mac with destructive confirmation.
- Revoking the current Mac routes through Sign Out and clearly states that this Mac will return to guest mode.
- Refresh/list/revoke errors remain visible and retryable; never optimistically remove a device before the server confirms.
- If a concurrent change makes the target stale, refresh and explain rather than treating it as success.
- Device count comes from the server response, not a local array count or pricing constant.

The Phase 2 limit-reached sheet remains the recovery path when the current Mac has no slot, so web device management is not required for this release.

## Downgrade and account lifecycle

- Verify the entitlement trigger handles Polar/admin transitions to Free, inactive, canceled, past due, or revoked.
- Keep the most recently verified active device; revoke all excess with `planDowngrade`.
- The retained device's next response shows its new `1 of 1` limit without reauthentication.
- Revoked online devices receive a specific plan-change explanation, stop cloud access, and return to guest.
- Re-upgrading to Pro raises capacity to three but does not silently reactivate revoked devices.
- Account deletion removes all device documents/summary before or alongside Auth deletion and tolerates partial prior deletion.
- A user-initiated local sign-out never waits indefinitely for remote release.

## Firestore enforcement rollout

Apply `signedInCommitPlusDevice(uid)` to:

- `entitlements/{uid}` reads from the macOS client;
- `users/{uid}/settings/app` reads/writes;
- `users/{uid}/gitProviderAccounts/*` reads/writes/deletes;
- `users/{uid}/repositoryBookmarks/*` reads/writes/deletes.

Keep these boundaries explicit:

- `featurePolicies/release` remains public and client read-only.
- Device registry remains server-write-only.
- Web profile/pricing APIs use verified Firebase ID tokens and Admin SDK; they do not consume or require a Mac slot.
- Local caches remain local-first but cannot upload/download through Firestore after revocation.

Rollout order:

1. Confirm Functions claim/replace/release/list/heartbeat/reconcile are deployed and healthy.
2. Publish the compatible macOS release and document that older builds must update for account/Pro/sync access.
3. Exercise Free first/second and Pro first/third/fourth Mac scenarios against staging/emulators.
4. Deploy Firestore rules.
5. Fetch and inspect active production rules source, then test one allowed active device and one revoked/unbound session.
6. Monitor only operational errors available from Firebase; do not add product analytics or device fingerprint telemetry.

## Landing-page copy and privacy

In `/Users/thanhtran/Project/Commit+/landing-page`:

- Clarify pricing language as `1 signed-in Mac` and `up to 3 signed-in Macs`; guest use remains uncounted.
- Update privacy policy statements that currently claim there are no accounts or device identifiers.
- Disclose Firebase account data, server-owned entitlement, a random app-generated device ID, generic device/app/OS metadata, and timestamps used solely for quota and account security.
- State explicitly that repository content, local paths, Git history, credentials, and Git activity are not included.
- Explain user controls: sign out, revoke/replace a Mac, and delete account data.
- Keep Terms/FAQ consistent where they currently imply that Commit+ has no account system.

## Expected file map

### macgit repository

- Add `macgit/Views/Account/ManageDevicesSheet.swift`.
- Modify `ManageAccountSheet.swift`, account sheet routing, and `AccountSessionController.swift`.
- Extend device access models/services from Phase 2 for list/revoke/current-device sign-out.
- Modify `functions/src/device-access.ts`, trigger/account deletion only for Phase 3 gaps found by end-to-end tests.
- Modify `firestore.rules` and `firebase-tests/firestore.rules.test.mjs` to enable final enforcement.
- Add/extend Manage Devices, downgrade, revocation, account deletion, and lifecycle tests.
- Add an operator/read-only verification script only if it avoids manual, error-prone production inspection; it must not contain credentials.

### landing-page repository

- Modify `components/pricing.tsx` and `components/pricing-page-content.tsx`.
- Modify `app/policy/page.tsx`.
- Review and update `app/terms/page.tsx`, `app/faq/page.tsx`, and profile copy only where their current claims conflict with the implemented account/device behavior.
- Add/update existing component or route tests for the changed disclosures/copy.

## Test plan

### Management and lifecycle

- Counts and labels for Free 1/1, Pro 1/3, 2/3, 3/3.
- List sorting/current marker and refresh/error states.
- Revoke other Mac, revoke current Mac, stale target, repeated revoke, and network failure.
- Downgrade chooses deterministic most-recent Mac and emits the correct reason to others.
- Upgrade increases capacity without resurrecting revoked records.
- Delete account cleans non-empty and partially deleted device subcollections.

### End-to-end enforcement

- Guest performs local Git and has no device document.
- Free first Mac claims and syncs; second cannot sync until replacement/cancel.
- Active Pro three Macs claim and sync; fourth cannot.
- Replaced/revoked token loses entitlement and settings/provider/bookmark access.
- Web profile/pricing token still reaches server APIs without creating a Mac slot.
- Offline active Mac retains cached UI/local state; once online, a revoked record fails closed and signs out.
- Legacy/unbound official build loses protected cloud access after final rules flip and receives update-required messaging where possible.

### Copy/privacy

- Pricing, in-app comparison, FAQ/Terms, and privacy policy consistently describe one versus three signed-in Macs.
- Privacy copy does not claim that accounts/device IDs are absent and does not imply repository telemetry.

## Acceptance criteria

- Users can see, revoke, and replace their own Mac slots without support intervention.
- Downgrade converges from three to one deterministically and does not touch local Git/data.
- Production Firestore rejects entitlement and sync access from unbound/revoked Mac sessions.
- Active device sessions continue entitlement and sync normally.
- Web account/billing access remains outside the Mac quota.
- Public disclosures accurately describe the minimal device registry.
- Deployment evidence includes actual active Functions/rules state, not only local tests or CLI success.

## Explicit non-goals

- No web Manage Devices screen in this release; the macOS limit sheet can replace a device after Firebase authentication.
- No support dashboard, organization/Team seat UI, automatic stale expiry, or usage analytics.
- No forced deletion of local data on sign-out/downgrade/revocation.
- No Git feature or provider-auth changes.

## Verification

- Run Functions and Firebase emulator/rules tests.
- Run focused Swift device/account/entitlement/settings/provider/bookmark tests.
- Run landing-page lint/typecheck/build and affected tests.
- Run `git diff --check` in both repositories.
- Run `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build` without launching the app.
- After separately authorized deployment, fetch active Functions revisions and Firestore rules source and record live allowed/denied smoke-test evidence.
- Keep runtime UI/manual QA explicit for sheet geometry, focus, VoiceOver order, offline transition, and live cross-Mac revocation.

## Result

- Self-service active-Mac count, current-device marker, refresh, and confirmed removal are available in Manage Account. The limit-recovery sheet provides atomic replacement when the current Mac has no slot.
- Backend downgrade reconciliation remains deterministic and account deletion clears device-owned records. List/revoke callables require an active bound Mac session.
- Firestore source rules and emulator tests enforce active device claims for entitlement and synced settings/provider/bookmark data, while the public release feature policy remains outside device quota.
- Landing pricing now says `1 signed-in Mac` and `up to 3 signed-in Macs`; FAQ, Terms, and Privacy explicitly separate optional official Commit+ cloud sessions from guest/local Git and self-operated AGPL source.
- Privacy copy discloses Firebase account/entitlement/sync data and the random app-generated UUID plus generic Mac/app/OS metadata, while excluding repository contents, paths, Git history/activity, and credentials from the device registry.
- Local verification: Functions tests 17/17, Firestore emulator rules tests 21/21 from Phase 1, focused macOS regression tests 36/36, macOS build passed, and landing production build passed. Landing lint is unavailable because the repository declares `eslint .` but does not include ESLint in its dependencies.
- Not performed: app release, Functions deploy, Firestore rules deploy, landing deploy, active-production source verification, or live multi-Mac/runtime UI QA.
