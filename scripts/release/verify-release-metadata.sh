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

assert_equal() {
  local label="$1"
  local actual="$2"
  local expected="$3"

  if [[ "$actual" != "$expected" ]]; then
    echo "$label mismatch: expected '$expected', got '$actual'" >&2
    exit 1
  fi

  echo "$label: $actual"
}

assert_equal "Bundle ID" "$BUNDLE_ID" "dev.thanhtran.macgit"
assert_equal "Marketing version" "$MARKETING_VERSION" "$EXPECTED_VERSION"
assert_equal "Build version" "$BUILD_VERSION" "$EXPECTED_BUILD"
assert_equal "Sparkle feed URL" "$FEED_URL" "$EXPECTED_FEED_URL"

if [[ -z "$PUBLIC_KEY" ]]; then
  echo "Sparkle public key is missing" >&2
  exit 1
fi
echo "Sparkle public key: present"

if [[ " $ARCHS " != *" arm64 "* ]]; then
  echo "Required arm64 architecture is missing; found: $ARCHS" >&2
  exit 1
fi
echo "Architectures: $ARCHS"

if ! printf '%s\n' "$SIGNING_DETAILS" | grep -F "Authority=Developer ID Application"; then
  echo "App is not signed with a Developer ID Application certificate" >&2
  printf '%s\n' "$SIGNING_DETAILS" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH"
xcrun stapler validate "$APP_PATH"
