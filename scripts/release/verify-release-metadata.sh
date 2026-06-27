#!/bin/zsh
set -euo pipefail

APP_PATH="${1:?usage: verify-release-metadata.sh <app-path> <version> <build> <feed-url>}"
EXPECTED_VERSION="${2:?usage: verify-release-metadata.sh <app-path> <version> <build> <feed-url>}"
EXPECTED_BUILD="${3:?usage: verify-release-metadata.sh <app-path> <version> <build> <feed-url>}"
EXPECTED_FEED_URL="${4:?usage: verify-release-metadata.sh <app-path> <version> <build> <feed-url>}"

INFO_PLIST="$APP_PATH/Contents/Info.plist"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/Commit+"

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST")
MARKETING_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
BUILD_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")
FEED_URL=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$INFO_PLIST")
PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$INFO_PLIST")
ARCHS=$(lipo -archs "$EXECUTABLE_PATH")
SIGNING_DETAILS=$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)

test "$BUNDLE_ID" = "com.thanhtran.macgit"
test "$MARKETING_VERSION" = "$EXPECTED_VERSION"
test "$BUILD_VERSION" = "$EXPECTED_BUILD"
test "$FEED_URL" = "$EXPECTED_FEED_URL"
test -n "$PUBLIC_KEY"
test "$ARCHS" = "arm64"
printf '%s\n' "$SIGNING_DETAILS" | grep -F "Authority=Developer ID Application"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH"
xcrun stapler validate "$APP_PATH"
