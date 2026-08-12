# Commit+ Account Device Limits Phase 2: macOS Session Activation and Limit Recovery UX

**Status:** completed locally; release and production deployment pending

**Implementation branch:** `codex/account-device-limits-phase-2`

## Goal

Make the macOS app claim and validate a device slot before exposing an authenticated Commit+ session, exchange temporary Firebase auth for a device-bound session, and provide clear recovery when Free/Pro capacity is full.

## Prerequisites and session kickoff

- Phase 1 must be merged to `main`, and its callable Functions must be available in the target Firebase environment.
- Read the roadmap, Phase 1 plan, `AccountSessionController`, `FirebaseAuthService`, entitlement/settings lifecycle, authentication views, and account tests.
- Start from a clean `main` and run `git switch -c codex/account-device-limits-phase-2`.
- Do not deploy enforcing Firestore rules until this phase's compatible app has been released according to Phase 3.

## Device identity

- Add a `DeviceIdentityProviding` protocol and Keychain implementation.
- Generate one random UUID on first access and persist it with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- Reuse the existing Keychain error-mapping style; never fall back to a hardware identifier.
- Capture a bounded, generic metadata payload: platform, model family, OS version, and app marketing version.
- If Keychain identity cannot be read or created, fail account activation with a user-facing error while leaving guest/local Git available.

## App-owned device access model

Add presentation-neutral types such as:

```text
DeviceAccessState
  unverified
  verifying
  active(summary, verification: live | cached)
  limitReached(limit, devices, pendingAccount)
  revoked(reason)
  failed(message, mayRetry)
```

- Keep the temporary Firebase-authenticated account separate from `AccountSessionState.authenticated` until claim succeeds.
- `AccountSessionController.account` becomes non-nil only for an active or valid cached device session.
- Store a small UID + local device ID + last verified timestamp cache. It is an offline UX hint, not quota authority.
- A cache is valid only when UID and ThisDeviceOnly Keychain ID both match. Clear it after explicit sign-out, definitive revocation, account deletion, or identity reset.

## Authentication and startup lifecycle

All email/password, Google, account creation, and account-link completion paths must converge on one activation coordinator:

1. Firebase provider authentication succeeds temporarily.
2. Claim the local device slot through Phase 1.
3. If accepted, exchange the returned custom token with Firebase Auth.
4. Confirm the device-bound claim matches the Keychain ID.
5. Only then publish `.authenticated`, start entitlement observation, start settings/provider/bookmark sync, and dismiss authentication UI.

At app startup:

- A persisted device-bound Firebase user plus matching cache may restore the account immediately for offline UX and then revalidate in background.
- A definitive revoked/missing-device response signs out and returns to guest.
- A transient network failure retains the cached active state and marks it offline/cached; it must not sign out or erase locally applied settings.
- A legacy persisted Firebase session without device claims attempts the one-time server claim migration when online. If full, show the same limit recovery UI. If offline, keep guest/local Git available and show verification required.
- A mismatched custom claim and local Keychain ID fails closed and signs out.

## Limit-reached recovery UX

Add a native `DeviceLimitSheet` presented after a temporary Firebase sign-in reaches capacity:

- Explain the actual plan and `1 of 1` or `3 of 3` limit.
- List server-returned active Macs with generic model, last active date, and a `This Mac` marker when applicable.
- Offer `Replace This Device...` on each other active Mac with destructive confirmation explaining that the selected Mac will be signed out when online.
- Replacement must be one atomic server call; do not revoke first and claim second.
- Offer `Retry` after plan upgrade/entitlement refresh.
- Offer `View Pricing` for Free and `Cancel` for every plan.
- Cancel signs out the temporary Firebase credential and returns to guest without changing existing slots.
- Keep the sheet open and preserve recoverable state on network/server failure.
- Do not allow Settings/entitlement listeners or Pro feature access behind this sheet before activation.

## Revocation and sync lifecycle

- Observe the current device document after activation. Active -> revoked/missing is a definitive session-loss event.
- On definitive loss: stop entitlement, settings, provider metadata, bookmarks, and other cloud listeners; reset effective account entitlement to Free; locally sign out Firebase; show the reason; preserve every local setting, repository, bookmark cache, and provider credential.
- On network/listener error: retain last verified state and local data, surface cached/offline status, and retry on app activation.
- Send a heartbeat at successful activation and at most once per 24 hours when the app becomes active. Do not turn it into telemetry.
- Explicit Sign Out attempts server release first, then always signs out locally. If release fails, explain that the remote slot may remain and can be replaced later.

## SwiftUI and concurrency requirements

- Views render state and callbacks only; orchestration remains in `AccountSessionController`/services.
- Keep controller and stored UI callbacks explicitly `@MainActor` where required by Swift 6.2.
- Construct immutable `Sendable` device/replacement requests before crossing `Task` boundaries.
- Use labeled buttons, text plus icons, confirmation dialogs for replacement, keyboard default/cancel behavior, and VoiceOver-friendly plan/device/status descriptions.
- Do not rely on color alone for active, cached, current, or revoked state.

## Expected file map

- Add `macgit/Models/AccountDeviceModels.swift`.
- Add `macgit/Services/DeviceIdentityStore.swift`.
- Add `macgit/Services/DeviceAccessProviding.swift`.
- Add `macgit/Services/FirebaseDeviceAccessService.swift` for Functions/Auth/Firestore integration.
- Modify `macgit/Services/AccountAuthenticating.swift` and `FirebaseAuthService.swift` only as needed for custom-token exchange and claim inspection.
- Modify `macgit/App/AccountSessionController.swift` for the unified activation/bootstrap/revocation lifecycle.
- Modify `macgit/App/macgitApp.swift` for protocol injection.
- Add `macgit/Views/Account/DeviceLimitSheet.swift`.
- Modify `AuthenticationSheet.swift`, `AccountToolbarMenu.swift`, and root account-sheet routing.
- Add focused tests: `DeviceIdentityStoreTests`, `DeviceAccessModelTests`, `FirebaseDeviceAccessServiceTests`, plus controller and authentication-presentation coverage.

## Test plan

### Identity and model

- First UUID creation, stable reread, ThisDeviceOnly accessibility, Keychain failure, and no hardware-derived fallback.
- Strict decode of server results, malformed response rejection, device sorting, current-device marker, and user-facing reasons.

### Controller lifecycle

- Every auth method claims before publishing authenticated state.
- Successful claim exchanges token, confirms claim, then starts each listener exactly once.
- Full Free/Pro state starts no listener and exposes replacement/cancel/retry.
- Cancel clears pending auth; replacement success activates; replacement failure preserves recovery state.
- Startup with matching live session, cached offline session, legacy unbound session, mismatched claim, revoked record, and network error.
- Explicit sign-out release success/failure both end locally signed out, with failure messaging only in the latter.
- Revocation resets entitlement and stops listeners without deleting/rolling back local data.
- Heartbeat is bounded to once per 24 hours.

### Presentation

- Correct `1 of 1` and `3 of 3` copy.
- Free shows pricing; Pro does not imply that upgrading beyond Pro increases the limit.
- Replace requires confirmation and identifies the target.
- Progress, retry, errors, Cancel/default shortcuts, VoiceOver labels, and non-color state cues are present.

## Acceptance criteria

- No macOS Firebase sign-in becomes a Commit+ authenticated session before device activation.
- Free second Mac and Pro fourth Mac cannot observe entitlement or start sync through the official app.
- Same-device reauthentication consumes no extra slot.
- Every auth/link/create/startup path reaches the same coordinator.
- Offline cached access is limited to a previously verified matching device and never creates a slot.
- Revocation signs the online app out of Commit+ while local Git continues unchanged.
- The app builds without launch and focused tests cover the stored callback/async paths.

## Explicit non-goals

- No Manage Devices screen outside the limit-recovery sheet; that lands in Phase 3.
- No landing-page/API/privacy changes.
- No production Firestore enforcement flip.
- No Git core, provider OAuth-device-flow, repository, or credential changes.

## Verification

- Run the new focused identity/service/controller/presentation tests and affected entitlement/settings tests.
- Run `git diff --check`.
- Run `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build`.
- Do not launch the app. Record limit-sheet geometry, focus, and live revocation as runtime QA still required.
- If Firebase XCTest bootstrapping aborts, do not repeat the same run; retain compile/build evidence and any pure tests that executed.

## Result

- Added a random per-installation UUID in ThisDeviceOnly Keychain plus generic Mac/app/OS metadata; no serial number, MAC address, Firebase Installation ID, or fingerprint is read or uploaded.
- All Firebase authentication paths now stop at a server-backed activation gate before `AccountSessionController.account` becomes available. Accepted devices exchange the callable token, verify its device claim, then start entitlement and sync lifecycle.
- Added Free/Pro capacity recovery with active-device listing, atomic replacement, pricing/retry/cancel actions, and destructive copy that explicitly preserves local repositories and Git data.
- Added current-device Firestore observation, definitive revocation handling, local-first cached startup, bounded heartbeat refresh, remote-slot release on sign-out, and self-service listing/removal in Manage Account.
- Added a separate bound-session revoke callable for removing another Mac; production Functions and enforcing Firestore rules remain undeployed.
- Verification: Functions tests passed 17/17; focused macOS device/account/entitlement/settings tests passed 36/36; `xcodebuild ... build` passed. The app was not launched. Sheet geometry, focus order, VoiceOver flow, offline transition, and cross-Mac live revocation still require runtime QA.
