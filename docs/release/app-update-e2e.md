# App Update E2E Verification

This checklist validates the full Sparkle upgrade path against a controlled HTTPS feed before the production appcast is allowed to advertise a new Commit+ release.

## Goal

Prove that a previously shipped, signed, and notarized Commit+ build:

1. silently discovers a newer eligible release from a controlled appcast,
2. shows the sidebar `Update` action,
3. hands off to Sparkle's standard release-notes and install flow,
4. relaunches into the expected newer version, and
5. clears the sidebar banner after the update completes.

## Prerequisites

- An older signed and notarized `Commit+.app` already installed at `/Applications/Commit+.app`.
- A newer signed and notarized release ZIP produced by the same pipeline used in `.github/workflows/release-app-update.yml`.
- Access to an HTTPS-hosted test appcast URL that is separate from the production feed.
- The Sparkle public key embedded in the app and the matching private key used to sign the test appcast entry.
- A clean way to inspect the updated app version after relaunch, such as Finder `Get Info` or:

```bash
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" /Applications/Commit+.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" /Applications/Commit+.app/Contents/Info.plist
```

## Prepare The Test Feed

1. Start from the release artifact produced by `scripts/release/build-release-archive.sh`, then run the same notarization and verification steps used by CI:

```bash
scripts/release/notarize-and-staple.sh "$ZIP_PATH" "$APP_PATH"
scripts/release/verify-release-metadata.sh "$APP_PATH" "$TAG_VERSION" "$BUILD_VERSION" "$TEST_FEED_URL"
```

2. Generate a test appcast entry for the newer ZIP with the same Sparkle `generate_appcast` flow used in CI.
3. Host the ZIP and the generated `appcast.xml` at an HTTPS URL that is not the production Pages feed.
4. Confirm the test feed serves the ZIP successfully before launching the older app:

```bash
curl --fail --silent --show-error --location "$TEST_FEED_URL" --output /dev/null
curl --fail --silent --show-error --location "$TEST_RELEASE_ZIP_URL" --output /dev/null
```

## Point The Older Build At The Test Feed

1. Install the previously shipped `Commit+.app` in `/Applications`.
2. Ensure that build is configured to read the controlled test appcast URL rather than the production feed.
3. Quit Commit+ if it is already running so the next launch performs a fresh startup check.

Use a test-only build or test-only release configuration for this step. Do not rewrite the production feed URL in the normal release target just to exercise the test flow.

## Verification Steps

1. Launch `/Applications/Commit+.app`.
2. Wait for the silent launch-time update metadata check to finish.
Expected result: no Sparkle alert appears automatically.
3. Open a repository window.
Expected result: the top of the sidebar shows `Update`.
4. Click `Update`.
Expected result: Sparkle's standard release-notes window opens for the newer release.
5. Start the download from Sparkle's window.
Expected result: the sidebar button changes to `Downloading…` and is disabled while the download is active.
6. Let Sparkle finish installation and relaunch the app.
Expected result: Commit+ relaunches successfully from `/Applications`.
7. Verify the relaunched build reports the expected version and build number.
8. Reopen a repository window after relaunch.
Expected result: the sidebar update banner is gone.

## Evidence To Capture

- The older app version and build number before the test.
- The test appcast URL used for qualification.
- The newer release ZIP URL referenced by the test appcast.
- A screenshot showing the sidebar `Update` state.
- A screenshot showing Sparkle's release-notes window.
- A screenshot showing the sidebar `Downloading…` state.
- The relaunched app version and build number after installation.

## Failure Handling

- If no sidebar banner appears, verify the old build is actually older than the test feed item and confirm the appcast points to a reachable ZIP.
- If Sparkle reports a signature, feed, or compatibility error, stop and fix the release artifact or appcast before touching the production feed.
- If the app updates but still shows the banner after relaunch, treat that as a release blocker because the launch-time check or eligibility state is inconsistent.
- If the test feed behaves unexpectedly, remove or replace the bad appcast entry before rerunning qualification.

## Exit Criteria

The production appcast can be updated only after all of these are true:

- The controlled test feed completed a full update from an older installed build to the new build.
- The sidebar behavior matched the expected `Update` then `Downloading…` states.
- Sparkle installed and relaunched successfully.
- The relaunched app matches the intended `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
- The updated app no longer advertises the same release after relaunch.
