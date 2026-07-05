# Firebase Foundation Design

**Date:** 2026-07-02  
**Status:** Approved design  
**Scope:** Commit+ account, Pro entitlement foundation, and basic settings sync

## Overview

Add an optional Firebase-backed Commit+ account without changing the app's guest-first local Git experience. Users can continue using every existing local feature without signing in. Authentication is required only for cloud-backed capabilities: settings sync, future billing, and future Git provider connections.

This foundation intentionally precedes GitHub, GitLab, and Bitbucket account integration. It establishes the app user, entitlement, security, and serverless infrastructure that those provider flows will later depend on.

## Product Decisions

- Commit+ remains fully usable without an account.
- The toolbar always exposes an `Account` menu.
- Phase-one authentication supports email/password and Google.
- `Sign in with Apple` is visible but disabled with `Coming later`.
- Email verification is not required.
- Firebase users represent Commit+ accounts, not Git provider accounts.
- GitHub, GitLab, and Bitbucket credentials are never linked to or persisted under Firebase Auth.
- Settings sync is available to every signed-in Free or Pro account.
- The project adopts the Firebase Apple SDK through Swift Package Manager, replacing the existing zero-external-dependencies constraint.

## Goals

- Provide optional Commit+ sign-in and account creation.
- Expose guest, Free, and Pro states from a persistent toolbar Account menu.
- Sync three global app preferences for Pro users.
- Model a server-controlled entitlement that can later be driven by Polar.
- Provide a safe admin mechanism for assigning test Pro access.
- Establish strict Firestore ownership and denial rules.
- Keep Firebase code isolated from Git and existing view state.

## Non-Goals

- Polar checkout, webhook, or customer portal integration.
- GitHub, GitLab, or Bitbucket OAuth/PAT integration.
- Persisting Git provider accounts or credentials in Firebase.
- Repository-history sync.
- Restoring Git accounts on another machine.
- Sign in with Apple implementation.
- Email verification enforcement.
- Syncing repository-specific or device-layout settings.

## Account Entry Points

### Toolbar Menu

The `Account` toolbar menu is always visible.

Guest state, in order:

1. Non-interactive `Not signed in` summary.
2. `Sign In...`
3. `Create Account...`
4. Separator.
5. `Upgrade to Pro...`

`Upgrade to Pro...` first routes through authentication. Until Polar is implemented, the billing action presents a clear `Coming later` state rather than starting a checkout.

Signed-in Free state, in order:

1. Email and `Free plan` summary.
2. `Manage Account...`
3. `Sync Settings` status and toggle, available to Free and Pro accounts.
4. Separator.
5. `Upgrade to Pro...`
6. Separator.
7. `Sign Out`

Signed-in Pro state, in order:

1. Email and `Pro plan` summary.
2. `Manage Account...`
3. `Sync Settings` status.
4. Separator.
5. `Manage Subscription...`
6. Separator.
7. `Sign Out`

During the Firebase-only phase, `Manage Subscription · Coming later` is disabled. It becomes `Manage Subscription...` and becomes active when Polar integration lands.

### Authentication Sheet

Use one compact native sheet with `Sign In` and `Create Account` modes.

The sheet contains:

- Email field.
- Password field.
- Primary sign-in or create-account action.
- `Forgot Password?` in sign-in mode.
- `Continue with Google`.
- Disabled `Sign in with Apple · Coming later`.
- A reminder that Commit+ remains usable locally without an account.

Email/password sign-up signs the user in immediately. Password reset uses Firebase's reset-email flow. Authentication errors are translated into concise, user-facing messages.

If Google and password credentials resolve to the same email, Commit+ asks the user to authenticate using the existing method before linking the new method to the same Firebase UID. It must not silently create duplicate Commit+ users.

### Manage Account Sheet

The sheet shows:

- Email and authentication method.
- Free or Pro badge.
- Settings sync control and status.
- Upgrade or subscription-management action.
- `Sign Out`.
- Destructive `Delete Account...` action.

Deleting an account requires recent authentication. It removes Firebase settings and entitlement records plus the Firebase Auth user, but never deletes local repositories or local Git data.

Signing out stops cloud listeners and uploads while retaining the currently applied settings locally.

## Architecture

### Client Components

`AccountSessionController`

- Owns guest, loading, authenticated, and auth-error states.
- Coordinates account creation, sign-in, linking, reset, sign-out, and deletion.
- Publishes a presentation-friendly account snapshot.

`FirebaseAuthService`

- Wraps Firebase Auth behind a protocol.
- Implements email/password and Google flows.
- Maps Firebase errors into app-owned error types.
- Allows unit tests to use a fake implementation.

`SettingsSyncService`

- Starts only when the current user is Pro and sync is enabled on that device.
- Owns initial merge, snapshot listening, debounced upload, feedback-loop suppression, and pause/resume.
- Communicates with `AppState` through a small settings snapshot rather than embedding Firebase logic in `AppState`.

`EntitlementStore`

- Observes the current user's entitlement document.
- Produces normalized Free, Pro-active, Pro-paused, and unavailable states.
- Is the single policy source for cloud feature gating.

Presentation views:

- `AccountToolbarMenu`
- `AuthenticationSheet`
- `ManageAccountSheet`

These views render state and issue intents; they do not call Firebase directly.

### Dependencies

Link only the required Firebase Apple SDK products:

- `FirebaseAuth`
- `FirebaseFirestore`

Firebase project configuration, Firestore rules, emulator configuration, the account-deletion function, and the admin entitlement script live in a focused Firebase support area rather than inside Git service files.

## Data Ownership

### Local State

`AppState` and `UserDefaults` remain the immediate source of truth for UI preferences. The following device-local value is added:

- `syncEnabled`, default `false` per device.

Firebase Auth owns persisted session credentials. Commit+ must not log Firebase tokens or passwords.

### Synced Settings

Only these `AppState` preferences sync in phase one:

- `showToolbarButtonText`
- `showSubmodules`
- `showSubtrees`

Firestore document:

```text
users/{uid}/settings/app
  schemaVersion: integer
  showToolbarButtonText: boolean
  showSubmodules: boolean
  showSubtrees: boolean
  updatedAt: server timestamp
```

Do not sync transient app state, history column widths, recent local paths, sidebar expansion, or repository settings.

### Entitlement

```text
entitlements/{uid}
  plan: free | pro
  access: active | inactive
  billingStatus: none | trialing | active | past_due | canceled
  source: admin_test | polar
  currentPeriodEnd: optional timestamp
  cancelAtPeriodEnd: boolean
  updatedAt: server timestamp
```

The client may read its own entitlement but may not create or modify it. Firebase Admin operations bypass client rules for test assignment and future Polar webhook updates.

An admin-only script assigns or revokes `source: admin_test` Pro access. No admin control is shipped inside Commit+.

## Settings Sync Lifecycle

### Eligibility

Sync runs only when both are true:

- A Firebase user is signed in.
- `syncEnabled` is true on the current device.

Guests see the control locked until sign-in. Free and Pro users can enable it.

### First Enable

- If no cloud settings document exists, upload the current local settings.
- If cloud settings exist and differ from local settings, ask the user to choose `Use Cloud Settings` or `Keep This Mac's Settings`.
- Cancel leaves sync disabled and changes neither side.

### Continuous Sync

- Local changes update UI and `UserDefaults` immediately.
- `SettingsSyncService` debounces cloud writes.
- A Firestore snapshot listener applies remote changes.
- Applying remote state must not trigger an upload feedback loop.
- Document-level last-write-wins using the server timestamp resolves simultaneous edits.
- Firestore offline behavior queues writes and resumes automatically without blocking local UI.

### Pause and Resume

- Turning sync off or signing out stops listeners and uploads but keeps local and cloud values.
- Entitlement changes do not affect settings sync.
- Sync errors appear in Account UI and never block Git operations.

## Firestore Security

Rules are deny-by-default.

- Authenticated users may read and write only `users/{uid}/settings/app` matching their UID.
- Settings writes validate the exact allowed fields and types.
- Authenticated users may read only their own `entitlements/{uid}`.
- Client create/update entitlement operations are denied.
- Server Admin SDK operations remain responsible for entitlement changes.

A callable `deleteAccount` function verifies Firebase authentication and recent-auth intent, deletes settings and entitlement data, then deletes the Firebase Auth user. Repeated calls are idempotent.

## Polar Compatibility

Polar is the future billing source of truth. Firestore remains the normalized entitlement cache used by the app.

Future billing flow:

1. An authenticated Cloud Function creates a Polar Checkout session with the Firebase UID as `external_customer_id`.
2. Polar sends signed subscription webhooks to a Cloud Function.
3. The function verifies signatures, deduplicates event IDs, maps Polar state into the entitlement document, and never trusts the browser success redirect.
4. `Manage Subscription...` asks a Function to create a Polar Customer Portal session using the Firebase UID.

Polar API credentials and webhook secrets live in Secret Manager. Billing identifiers and raw webhook payloads are not exposed to the app.

## Future Repository History

Repository history is a separate, opt-in phase and defaults off because private repository names are sensitive metadata.

The existing `RecentRepository` remains local because it contains a machine-specific filesystem path. A future cloud model may store only provider, normalized owner/repository identity, sanitized remote URL, display name, and last-opened timestamp. It must never store tokens, local paths, or Git linked-account identifiers.

On a new machine, Repo Picker may show `Previously Used Repositories`. Selecting an unavailable item asks the user to connect the relevant provider locally, choose a destination, and clone it.

## Future Git Provider Accounts

GitHub, GitLab, and Bitbucket connections remain separate from Firebase Auth:

- Provider account metadata stays local in Application Support.
- Access and refresh tokens stay in macOS Keychain.
- OAuth Functions perform only transient code exchange and refresh work.
- Firebase does not persist linked Git accounts.
- Reinstalling or moving to another Mac requires reconnecting provider accounts.

This explicit local-only boundary supports the product's privacy message: Commit+ does not store users' Git provider login credentials or linked-account inventory in its cloud database.

## Error Handling

- Auth failures remain inside the auth sheet with actionable wording.
- Network loss does not sign the user out or block local Git work.
- Firestore permission failures stop sync and expose an Account status error.
- Missing entitlement is treated as Free, not as an application failure.
- Malformed cloud settings are rejected without overwriting valid local values.
- Account deletion failure leaves the user signed in and reports which step failed.
- Admin and billing failures never grant Pro by default.

## Testing

### Unit Tests

- Guest, Free, Pro-active, and Pro-paused Account menu policy.
- Email/password and Google auth state transitions through fakes.
- Account-linking error and recovery behavior.
- Initial sync decisions for missing, equal, and conflicting cloud settings.
- Debounce and feedback-loop suppression.
- Entitlement gating, pause, and automatic resume.
- Malformed settings and missing-entitlement fallback.

### Firebase Emulator Tests

- A user can read and write only their settings document.
- Settings schema validation rejects unknown fields and wrong types.
- A user cannot read another user's settings or entitlement.
- A client cannot self-assign or modify Pro.
- Admin assignment produces the expected Pro state.
- Account deletion removes owned cloud data and auth identity.

### Verification

Run:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test
```

Do not launch the app after successful automated verification; manual UI testing remains with the user.

## Delivery Boundary

The Firebase foundation is complete when guest behavior is unchanged, authentication and Account UI work, three settings sync for every signed-in account, entitlement rules prevent self-upgrade, admin test assignment works, account deletion is safe, emulator tests pass, and the full macOS test suite is green.

Polar billing, provider authentication, and repository-history sync each require their own follow-up design and roadmap.
