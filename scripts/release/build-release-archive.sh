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
APP_PATH="$RUNNER_TEMP/Commit+.app"
ZIP_NAME="Commit+-${TAG_VERSION}-arm64.zip"
ZIP_PATH="$RUNNER_TEMP/$ZIP_NAME"

rm -rf "$ARCHIVE_PATH" "$APP_PATH" "$ZIP_PATH"

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

cp -R "$ARCHIVE_PATH/Products/Applications/Commit+.app" "$APP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "ARCHIVE_PATH=$ARCHIVE_PATH" >> "$GITHUB_ENV"
echo "APP_PATH=$APP_PATH" >> "$GITHUB_ENV"
echo "ZIP_PATH=$ZIP_PATH" >> "$GITHUB_ENV"
echo "ZIP_NAME=$ZIP_NAME" >> "$GITHUB_ENV"
