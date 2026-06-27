# Direct App Update Phase 3: Release Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish signed, notarized, Sparkle-compatible Apple Silicon releases from Git tags to GitHub Releases, then update the public appcast on GitHub Pages only after the artifact is verified.

**Architecture:** Keep all release logic in repository automation and helper scripts rather than app runtime code. The workflow validates versions, runs tests, archives the app, signs and notarizes it, zips it, signs the enclosure for Sparkle, publishes the release asset, verifies public reachability, and updates the appcast last.

**Tech Stack:** GitHub Actions, shell scripts, Xcode command-line tools, `notarytool`, `stapler`, Sparkle signing utilities.

**Design spec:** [docs/superpowers/specs/2026-06-27-app-update-design.md](../specs/2026-06-27-app-update-design.md)

---

## File Structure

- Create `.github/workflows/release-app-update.yml`: stable release workflow.
- Create `scripts/release/verify-release-metadata.sh`: local metadata and architecture checks.
- Create `scripts/release/notarize-and-staple.sh`: notarization wrapper.
- Create `scripts/release/publish-appcast.sh`: appcast update helper.
- Create `docs/release/app-update-secrets.md`: CI secret inventory and setup notes.

## Task 1: Add Release Verification Script

**Files:**
- Create: `scripts/release/verify-release-metadata.sh`

- [ ] **Step 1: Add the verification script**

Create `scripts/release/verify-release-metadata.sh`:

```bash
#!/bin/zsh
set -euo pipefail

APP_PATH="$1"
EXPECTED_VERSION="$2"
EXPECTED_BUILD="$3"

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Contents/Info.plist")
MARKETING_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
BUILD_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist")
ARCHS=$(lipo -archs "$APP_PATH/Contents/MacOS/Commit+")

test "$BUNDLE_ID" = "com.thanhtran.macgit"
test "$MARKETING_VERSION" = "$EXPECTED_VERSION"
test "$BUILD_VERSION" = "$EXPECTED_BUILD"
test "$ARCHS" = "arm64"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH"
```

- [ ] **Step 2: Make the script executable and smoke test its usage string**

Run:

```bash
chmod +x scripts/release/verify-release-metadata.sh
scripts/release/verify-release-metadata.sh
```

Expected: non-zero exit because required arguments are missing.

## Task 2: Add The GitHub Actions Workflow

**Files:**
- Create: `.github/workflows/release-app-update.yml`
- Create: `scripts/release/notarize-and-staple.sh`
- Create: `scripts/release/publish-appcast.sh`

- [ ] **Step 3: Add the notarization helper**

Create `scripts/release/notarize-and-staple.sh`:

```bash
#!/bin/zsh
set -euo pipefail

ARCHIVE_PATH="$1"
APP_PATH="$2"

xcrun notarytool submit "$ARCHIVE_PATH" \
  --key "$APPSTORE_CONNECT_PRIVATE_KEY_PATH" \
  --key-id "$APPSTORE_CONNECT_KEY_ID" \
  --issuer "$APPSTORE_CONNECT_ISSUER_ID" \
  --wait

xcrun stapler staple "$APP_PATH"
```

- [ ] **Step 4: Add the appcast publish helper**

Create `scripts/release/publish-appcast.sh`:

```bash
#!/bin/zsh
set -euo pipefail

APPCAST_PATH="$1"
OUTPUT_PATH="$2"

cp "$APPCAST_PATH" "$OUTPUT_PATH"
```

- [ ] **Step 5: Add the workflow skeleton**

Create `.github/workflows/release-app-update.yml`:

```yaml
name: Release App Update

on:
  push:
    tags:
      - "v*"

jobs:
  release:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Validate version
        run: |
          TAG_VERSION="${GITHUB_REF_NAME#v}"
          PROJECT_VERSION=$(xcodebuild -project macgit.xcodeproj -scheme macgit -showBuildSettings | awk '/MARKETING_VERSION/ { print $3; exit }')
          test "$TAG_VERSION" = "$PROJECT_VERSION"
      - name: Run tests
        run: xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test
      - name: Archive app
        run: xcodebuild -project macgit.xcodeproj -scheme macgit -configuration Release -destination 'platform=macOS,arch=arm64' build
```

- [ ] **Step 6: Extend the workflow with signing, notarization, ZIP creation, release upload, reachability check, and appcast publish**

Append to `.github/workflows/release-app-update.yml`:

```yaml
      - name: Notarize and staple
        run: scripts/release/notarize-and-staple.sh "$RUNNER_TEMP/Commit+.zip" "$RUNNER_TEMP/Commit+.app"
      - name: Verify release metadata
        run: scripts/release/verify-release-metadata.sh "$RUNNER_TEMP/Commit+.app" "${GITHUB_REF_NAME#v}" "$GITHUB_RUN_NUMBER"
      - name: Publish GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: ${{ runner.temp }}/Commit+.zip
      - name: Verify public asset
        run: curl --fail --location "$RELEASE_ASSET_URL" --output /dev/null
      - name: Publish appcast
        run: scripts/release/publish-appcast.sh "$RUNNER_TEMP/appcast.xml" docs/appcast.xml
```

- [ ] **Step 7: Commit the phase work**

Run:

```bash
git add .github/workflows/release-app-update.yml scripts/release/verify-release-metadata.sh scripts/release/notarize-and-staple.sh scripts/release/publish-appcast.sh docs/release/app-update-secrets.md docs/superpowers/plans/2026-06-27-app-update-roadmap.md
git commit -m "ci: automate app update releases"
```

Expected: a clean commit on `codex/app-update-phase-3-release-automation`.
