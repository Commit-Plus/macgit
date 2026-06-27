# App Update Release Runbook

This runbook is the operator checklist for publishing a production Commit+ app update through GitHub Releases and the stable Sparkle appcast.

## Release Preconditions

1. Confirm the target release version is represented as a semantic tag like `v1.2.3`.
2. Confirm `MARKETING_VERSION` matches that tag without the leading `v`.
3. Confirm `CURRENT_PROJECT_VERSION` will increase relative to the previous public release.
4. Confirm the GitHub Actions secrets and variables in [app-update-secrets.md](app-update-secrets.md) are present and current.
5. Confirm GitHub Pages is still configured to deploy from GitHub Actions.

## What The Release Workflow Guarantees

The `Release App Update` workflow in [.github/workflows/release-app-update.yml](../../../.github/workflows/release-app-update.yml) performs the release in this order:

1. Validates the pushed tag format and version alignment.
2. Resolves the pinned Sparkle checkout.
3. Runs the full `xcodebuild ... test` suite.
4. Archives a Release `Commit+.app` for macOS.
5. Imports signing assets into a temporary keychain.
6. Notarizes the ZIP, staples the app, and rebuilds the ZIP after stapling.
7. Verifies bundle metadata, Sparkle feed configuration, code signing, hardened runtime, Gatekeeper acceptance, and `arm64` architecture.
8. Creates a stable GitHub Release and uploads the signed ZIP.
9. Waits until the public release asset is reachable.
10. Generates a signed Sparkle `appcast.xml`.
11. Publishes the appcast to GitHub Pages.

The appcast is intentionally last. If an earlier step fails, clients should never discover a partially published release.

## Production Release Checklist

1. Push the stable tag that should ship, for example:

```bash
git tag v1.2.3
git push origin v1.2.3
```

2. Wait for `Release App Update` to finish successfully in GitHub Actions.
3. Open the GitHub Release for that tag.
Expected result: it is not a draft or prerelease, and it contains the signed Apple Silicon ZIP.
4. Download the released ZIP and verify Gatekeeper locally:

```bash
spctl --assess --type execute --verbose /path/to/Commit+.app
```

5. Confirm the published appcast is reachable:

```bash
curl --fail --silent --show-error --location https://tranthanh98.github.io/macgit/appcast.xml --output /dev/null
```

6. Inspect the appcast entry and confirm it references the just-published GitHub Release asset.
7. Run the controlled-feed checklist in [app-update-e2e.md](app-update-e2e.md) against the release before relying on the production feed rollout.
8. Record the qualified version, build number, release URL, and qualification date in the release notes or team log.

## Rollback Guidance

If publication fails before the appcast changes, fix the workflow issue and rerun from a corrected tag or release process.

If a bad release has already reached the public appcast:

1. Remove or replace the bad appcast entry first so installed clients stop discovering it.
2. If necessary, remove the GitHub Release asset or the GitHub Release itself after the feed no longer points at it.
3. Investigate whether the failure came from signing, notarization, appcast metadata, or runtime behavior discovered during qualification.
4. Publish a corrected release only after the controlled-feed checklist passes again.

## Operational Notes

- `SPARKLE_FEED_URL` in GitHub Actions must stay aligned with `SUFeedURL` in the app bundle metadata.
- The repository stores only the Sparkle public key. Keep the private Ed25519 key in GitHub Actions secrets only.
- The production feed should contain only stable releases that completed the full workflow and qualification steps.
- Treat any mismatch between the release ZIP, appcast enclosure metadata, and signed app bundle as a release blocker.
