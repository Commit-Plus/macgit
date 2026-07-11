# Firebase Setup

Commit+ keeps Firebase configuration local. The app remains usable in guest mode when the configuration file is absent.

## Firebase project

1. Create or select the Firebase project used by Commit+.
2. Register an Apple app with bundle ID `dev.thanhtran.macgit`.
3. In Firebase Authentication, enable:
   - Email/Password.
   - Google.
4. Do not enable email verification as an application requirement for the Firebase foundation phases.
5. Create a Cloud Firestore database. Deploy the checked-in Firestore rules before using production data.

## Google OAuth client

Google Sign-In on macOS uses an OAuth client whose application type is **iOS**.

1. Open Google Cloud Console for the same project.
2. Create or verify an iOS OAuth client with bundle ID `dev.thanhtran.macgit`.
3. Return to Firebase Authentication, verify Google remains enabled, and download a fresh `GoogleService-Info.plist`.
4. Confirm the downloaded file contains `CLIENT_ID` and `REVERSED_CLIENT_ID`.

## Local app configuration

1. Save the downloaded file at:

   ```text
   macgit/GoogleService-Info.plist
   ```

2. Do not commit this file. The path is ignored by Git.
3. Add the plist's `REVERSED_CLIENT_ID` as a URL scheme for the `macgit` target before enabling the Phase 1 Google sign-in flow.
4. Never print `API_KEY`, OAuth client IDs, or Firebase tokens in test logs.

`FirebaseBootstrap` looks for `GoogleService-Info.plist` in the application bundle. If it is absent or invalid, bootstrap reports `missingConfiguration` and Commit+ continues in guest mode.

## Firebase CLI and emulators

Install and authenticate the Firebase CLI:

```bash
npm install --global firebase-tools
firebase login
firebase use --add
```

Phase 2 adds Firestore and Functions emulator configuration. Run the commands from the repository root so `firebase.json` and rules files resolve consistently.

Install the repository-local JavaScript dependencies:

```bash
npm --prefix firebase-tests install
npm --prefix functions install
npm --prefix scripts/firebase install
```

Run Firestore rules tests and Functions tests:

```bash
npx firebase-tools emulators:exec --project macgit-local --only firestore "npm --prefix firebase-tests test"
npm --prefix functions test
```

Run the complete Firebase foundation emulator suite with Auth, Firestore, and Functions available:

```bash
firebase emulators:exec --project macgit-local --only auth,firestore,functions "npm --prefix firebase-tests test"
```

## Settings sync

Settings sync is optional and device-local. It starts when a Free or Pro user is signed in and enables **Sync Settings** on that Mac. Guest workflows remain fully local, and entitlement changes do not pause cloud observation or uploads.

The first time a Mac finds different local and cloud values, Commit+ asks whether to use the cloud values or keep that Mac's values. Canceling this choice disables sync on that device. After the initial choice, local changes are debounced and remote changes apply without being uploaded back as echoes.

The only synchronized values are:

- Toolbar button text visibility.
- Submodule visibility.
- Subtree visibility.

Firestore stores these values at `users/{uid}/settings/app`. The document must contain exactly `schemaVersion`, the three boolean settings, and the server timestamp `updatedAt`. Repository state, credentials, Git history, and other preferences are never included.

## Test Pro entitlement assignment

`scripts/firebase/set-entitlement.mjs` is an operator-only Admin SDK tool. It is never bundled into Commit+ and must never be exposed as a client action.

For a deployed Firebase project, authenticate Application Default Credentials and select the project before using the script:

```bash
gcloud auth application-default login
export GOOGLE_CLOUD_PROJECT="your-firebase-project-id"
node scripts/firebase/set-entitlement.mjs <firebase-uid> grant
node scripts/firebase/set-entitlement.mjs <firebase-uid> revoke
```

Against the local Firestore emulator, set the emulator host and project explicitly:

```bash
export FIRESTORE_EMULATOR_HOST="127.0.0.1:8080"
export GCLOUD_PROJECT="macgit-local"
node scripts/firebase/set-entitlement.mjs <firebase-uid> grant
node scripts/firebase/set-entitlement.mjs <firebase-uid> revoke
```

The grant command writes active test Pro access with `source: admin_test`. The revoke command writes a normalized Free entitlement. Do not run this script with production credentials unless the target UID and requested mode have been independently verified.

## Validation

Check required local keys without printing their values:

```bash
for key in BUNDLE_ID PROJECT_ID GOOGLE_APP_ID CLIENT_ID REVERSED_CLIENT_ID IS_SIGNIN_ENABLED; do
  /usr/libexec/PlistBuddy -c "Print :$key" macgit/GoogleService-Info.plist >/dev/null
done
```

The `BUNDLE_ID` value must equal `dev.thanhtran.macgit` and `IS_SIGNIN_ENABLED` must be `true`.
