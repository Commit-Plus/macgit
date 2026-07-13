#!/bin/zsh
set -euo pipefail

TAG_VERSION="${1:?usage: build-release-archive.sh <tag-version> <build-version>}"
BUILD_VERSION="${2:?usage: build-release-archive.sh <tag-version> <build-version>}"

: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_ENV:?GITHUB_ENV is required}"
: "${KEYCHAIN_PATH:?KEYCHAIN_PATH is required}"
: "${PROVISIONING_PROFILE_UUID:?PROVISIONING_PROFILE_UUID is required}"
: "${SPARKLE_PUBLIC_ED_KEY:?SPARKLE_PUBLIC_ED_KEY is required}"

ARCHIVE_PATH="$RUNNER_TEMP/Commit+.xcarchive"
EXPORT_PATH="$RUNNER_TEMP/CommitPlusExport"
EXPORT_OPTIONS_PATH="$RUNNER_TEMP/DeveloperIDExportOptions.plist"
APP_PATH="$EXPORT_PATH/Commit+.app"
ZIP_NAME="Commit+-${TAG_VERSION}-arm64.zip"
ZIP_PATH="$RUNNER_TEMP/$ZIP_NAME"

rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$EXPORT_OPTIONS_PATH" "$ZIP_PATH"

xcodebuild archive \
  -project macgit.xcodeproj \
  -scheme macgit \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  MARKETING_VERSION="$TAG_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_VERSION" \
  SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY" \
  OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN_PATH"

/usr/libexec/PlistBuddy -c 'Clear dict' "$EXPORT_OPTIONS_PATH"
/usr/libexec/PlistBuddy -c 'Add :method string developer-id' "$EXPORT_OPTIONS_PATH"
/usr/libexec/PlistBuddy -c 'Add :signingStyle string manual' "$EXPORT_OPTIONS_PATH"
/usr/libexec/PlistBuddy -c 'Add :teamID string HNJ5KZ2LMD' "$EXPORT_OPTIONS_PATH"
/usr/libexec/PlistBuddy -c 'Add :signingCertificate string Developer ID Application' "$EXPORT_OPTIONS_PATH"
/usr/libexec/PlistBuddy -c 'Add :provisioningProfiles dict' "$EXPORT_OPTIONS_PATH"
/usr/libexec/PlistBuddy -c "Add :provisioningProfiles:dev.thanhtran.macgit string $PROVISIONING_PROFILE_UUID" "$EXPORT_OPTIONS_PATH"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PATH"

test -d "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "ARCHIVE_PATH=$ARCHIVE_PATH" >> "$GITHUB_ENV"
echo "APP_PATH=$APP_PATH" >> "$GITHUB_ENV"
echo "ZIP_PATH=$ZIP_PATH" >> "$GITHUB_ENV"
echo "ZIP_NAME=$ZIP_NAME" >> "$GITHUB_ENV"
