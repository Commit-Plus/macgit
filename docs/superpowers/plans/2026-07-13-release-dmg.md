# Commit+ DMG Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish a notarized DMG for manual installation alongside the existing notarized ZIP used by Sparkle.

**Architecture:** Keep the qualified ZIP and appcast path unchanged. Add focused scripts that create a compressed DMG from the already stapled app, notarize and staple the DMG, and verify its layout and Gatekeeper status; the GitHub Actions workflow coordinates both assets and publishes only the ZIP to `generate_appcast`.

**Tech Stack:** zsh, `hdiutil`, `xcrun notarytool`, `xcrun stapler`, `codesign`, `spctl`, GitHub Actions, Sparkle 2.9.3.

## Global Constraints

- Publish `Commit+-<version>-arm64.dmg` for landing-page and manual downloads.
- Keep `Commit+-<version>-arm64.zip` as the sole Sparkle appcast payload.
- The DMG contains `Commit+.app` and an `Applications` symlink.
- Do not re-sign `Commit+.app` after its notarization ticket has been stapled.
- Do not add a custom DMG background or icon layout in this iteration.
- Do not modify the existing `v1.0.1` release; the first intended DMG release is `v1.0.2`.

---

### Task 1: Create the compressed installation DMG

**Files:**
- Create: `scripts/release/create-dmg.sh`

**Interfaces:**
- Consumes: `create-dmg.sh <app-path> <tag-version>` plus `RUNNER_TEMP` and `GITHUB_ENV`.
- Produces: `DMG_PATH` and `DMG_NAME` in `GITHUB_ENV`.

- [ ] **Step 1: Add argument and environment validation**

Start the script with the repository AGPL header, `#!/bin/zsh`, `set -euo pipefail`, two positional arguments, and required `RUNNER_TEMP`/`GITHUB_ENV` checks.

- [ ] **Step 2: Create a deterministic DMG staging directory**

Use these paths and names:

```zsh
DMG_NAME="Commit+-${TAG_VERSION}-arm64.dmg"
DMG_PATH="$RUNNER_TEMP/$DMG_NAME"
DMG_SOURCE_DIR="$RUNNER_TEMP/CommitPlusDMG"

rm -rf "$DMG_SOURCE_DIR" "$DMG_PATH"
mkdir -p "$DMG_SOURCE_DIR"
ditto "$APP_PATH" "$DMG_SOURCE_DIR/Commit+.app"
ln -s /Applications "$DMG_SOURCE_DIR/Applications"
```

- [ ] **Step 3: Build the read-only compressed image**

```zsh
hdiutil create \
  -volname "Commit+" \
  -srcfolder "$DMG_SOURCE_DIR" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$DMG_PATH"

test -f "$DMG_PATH"
echo "DMG_PATH=$DMG_PATH" >> "$GITHUB_ENV"
echo "DMG_NAME=$DMG_NAME" >> "$GITHUB_ENV"
```

- [ ] **Step 4: Verify script structure**

Run:

```bash
zsh -n scripts/release/create-dmg.sh
```

Expected: exit 0.

- [ ] **Step 5: Commit the DMG creation unit**

```bash
git add scripts/release/create-dmg.sh
git commit -m "feat: create DMG release artifact"
```

### Task 2: Notarize, staple, and verify the DMG

**Files:**
- Create: `scripts/release/notarize-dmg.sh`
- Create: `scripts/release/verify-dmg.sh`

**Interfaces:**
- Consumes: `notarize-dmg.sh <dmg-path>` and App Store Connect key environment values already imported by `import-signing-assets.sh`.
- Consumes: `verify-dmg.sh <dmg-path>`.
- Produces: a stapled DMG that passes Gatekeeper and layout verification.

- [ ] **Step 1: Implement DMG notarization with issue-log output**

Use the same JSON status handling as `notarize-and-staple.sh`, with DMG-specific result paths:

```zsh
SUBMISSION_RESULT_PATH="${RUNNER_TEMP:-/tmp}/dmg-notary-submission.json"
NOTARY_LOG_PATH="${RUNNER_TEMP:-/tmp}/dmg-notary-log.json"

xcrun notarytool submit "$DMG_PATH" \
  --key "$APPSTORE_CONNECT_API_KEY_PATH" \
  --key-id "$APPSTORE_CONNECT_KEY_ID" \
  --issuer "$APPSTORE_CONNECT_ISSUER_ID" \
  --wait \
  --output-format json | tee "$SUBMISSION_RESULT_PATH"
```

If status is not `Accepted`, download and print `notarytool log` and exit 1. On acceptance, run:

```zsh
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
```

- [ ] **Step 2: Implement mounted-image verification with guaranteed detach**

Attach without opening Finder and capture the device:

```zsh
MOUNT_POINT="$RUNNER_TEMP/CommitPlusDMGVerify"
ATTACH_PLIST="$RUNNER_TEMP/CommitPlusDMGAttach.plist"
mkdir -p "$MOUNT_POINT"

hdiutil attach "$DMG_PATH" \
  -nobrowse \
  -readonly \
  -mountpoint "$MOUNT_POINT" \
  -plist > "$ATTACH_PLIST"

DEVICE=$(/usr/libexec/PlistBuddy -c 'Print :system-entities:0:dev-entry' "$ATTACH_PLIST")
trap 'hdiutil detach "$DEVICE" >/dev/null 2>&1 || true' EXIT
```

Verify `Commit+.app` is a directory, `Applications` is a symlink to `/Applications`, then run:

```zsh
codesign --verify --deep --strict --verbose=2 "$MOUNT_POINT/Commit+.app"
spctl --assess --type execute --verbose "$MOUNT_POINT/Commit+.app"
xcrun stapler validate "$DMG_PATH"
hdiutil verify "$DMG_PATH"
```

- [ ] **Step 3: Verify both scripts' syntax**

Run:

```bash
zsh -n scripts/release/notarize-dmg.sh scripts/release/verify-dmg.sh
```

Expected: exit 0.

- [ ] **Step 4: Commit the DMG qualification unit**

```bash
git add scripts/release/notarize-dmg.sh scripts/release/verify-dmg.sh
git commit -m "feat: notarize and verify DMG releases"
```

### Task 3: Publish ZIP and DMG while preserving ZIP-only appcast generation

**Files:**
- Modify: `.github/workflows/release-app-update.yml`
- Modify: `docs/release/app-update-runbook.md`

**Interfaces:**
- Consumes: `DMG_PATH` and `DMG_NAME` exported by Task 1.
- Produces: two GitHub Release assets and the unchanged ZIP-based appcast.

- [ ] **Step 1: Add DMG creation, notarization, and verification steps**

Insert after `Verify release metadata`:

```yaml
      - name: Create DMG
        run: scripts/release/create-dmg.sh "$APP_PATH" "$TAG_VERSION"

      - name: Notarize and staple DMG
        run: scripts/release/notarize-dmg.sh "$DMG_PATH"
        env:
          APPSTORE_CONNECT_KEY_ID: ${{ secrets.APPSTORE_CONNECT_KEY_ID }}
          APPSTORE_CONNECT_ISSUER_ID: ${{ secrets.APPSTORE_CONNECT_ISSUER_ID }}

      - name: Verify DMG
        run: scripts/release/verify-dmg.sh "$DMG_PATH"
```

- [ ] **Step 2: Upload both artifacts idempotently**

Change existing create/upload commands to pass both `"$ZIP_PATH"` and `"$DMG_PATH"`; keep `--clobber` on retries.

- [ ] **Step 3: Verify both public asset URLs**

Export `ZIP_RELEASE_ASSET_URL` and `DMG_RELEASE_ASSET_URL`, then loop over both URLs with the existing twelve-attempt retry behavior. Do not change the download prefix passed to `generate-appcast.sh`.

- [ ] **Step 4: Keep appcast input ZIP-only**

Confirm the `Generate appcast` step still invokes:

```yaml
scripts/release/generate-appcast.sh "$GITHUB_REF_NAME" "$ZIP_NAME" "$ZIP_PATH" "$RUNNER_TEMP/appcast.xml"
```

The DMG must never be copied into `APPCAST_WORK_DIR`.

- [ ] **Step 5: Update the release runbook**

Document that landing pages link to the DMG, Sparkle uses the ZIP, both must be notarized/reachable, and release retries replace both assets.

- [ ] **Step 6: Validate workflow, scripts, and app build**

Run:

```bash
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/release-app-update.yml")'
zsh -n scripts/release/*.sh
git diff --check
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```

Expected: YAML parse exit 0, all shell syntax checks exit 0, no diff errors, and `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit workflow integration**

```bash
git add .github/workflows/release-app-update.yml docs/release/app-update-runbook.md
git commit -m "feat: publish notarized DMG releases"
```

### Task 4: Final branch verification

**Files:**
- Verify only; no planned modifications.

**Interfaces:**
- Consumes: completed Tasks 1-3.
- Produces: evidence that the branch is ready to push and tag as `v1.0.2` after merge.

- [ ] **Step 1: Confirm the branch and clean change scope**

Run:

```bash
git branch --show-current
git status --short
git diff main...HEAD --stat
```

Expected: branch `codex/release-dmg`; only the spec, plan, DMG scripts, workflow, and release runbook differ from `main`.

- [ ] **Step 2: Repeat the full verification gate**

Run the Task 3 Step 6 commands again and retain the exit codes/output.

- [ ] **Step 3: Inspect final history**

Run:

```bash
git log --oneline main..HEAD
```

Expected: focused commits for design, plan, DMG creation, DMG qualification, and workflow integration.
