#!/bin/zsh
set -euo pipefail

: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_ENV:?GITHUB_ENV is required}"
: "${MACOS_CERTIFICATE_P12_BASE64:?MACOS_CERTIFICATE_P12_BASE64 is required}"
: "${MACOS_CERTIFICATE_PASSWORD:?MACOS_CERTIFICATE_PASSWORD is required}"
: "${MACOS_KEYCHAIN_PASSWORD:?MACOS_KEYCHAIN_PASSWORD is required}"
: "${MACOS_PROVISIONING_PROFILE_BASE64:?MACOS_PROVISIONING_PROFILE_BASE64 is required}"
: "${APPSTORE_CONNECT_KEY_ID:?APPSTORE_CONNECT_KEY_ID is required}"
: "${APPSTORE_CONNECT_ISSUER_ID:?APPSTORE_CONNECT_ISSUER_ID is required}"
: "${APPSTORE_CONNECT_API_KEY_BASE64:?APPSTORE_CONNECT_API_KEY_BASE64 is required}"

KEYCHAIN_PATH="$RUNNER_TEMP/app-signing.keychain-db"
CERT_PATH="$RUNNER_TEMP/developer-id-application.p12"
PROVISIONING_PROFILE_PATH="$RUNNER_TEMP/CommitPlus_DeveloperID.provisionprofile"
PROVISIONING_PROFILE_PLIST_PATH="$RUNNER_TEMP/CommitPlus_DeveloperID.plist"
API_KEY_PATH="$RUNNER_TEMP/AuthKey_${APPSTORE_CONNECT_KEY_ID}.p8"
EXPECTED_TEAM_ID="HNJ5KZ2LMD"
EXPECTED_BUNDLE_ID="dev.thanhtran.macgit"

decode_base64() {
  if base64 --help 2>/dev/null | grep -q -- '--decode'; then
    base64 --decode
  elif base64 --help 2>/dev/null | grep -q '\-D'; then
    base64 -D
  else
    base64 -d
  fi
}

echo "$MACOS_CERTIFICATE_P12_BASE64" | decode_base64 > "$CERT_PATH"
echo "$MACOS_PROVISIONING_PROFILE_BASE64" | decode_base64 > "$PROVISIONING_PROFILE_PATH"
echo "$APPSTORE_CONNECT_API_KEY_BASE64" | decode_base64 > "$API_KEY_PATH"

security cms -D -i "$PROVISIONING_PROFILE_PATH" > "$PROVISIONING_PROFILE_PLIST_PATH"
PROFILE_UUID=$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$PROVISIONING_PROFILE_PLIST_PATH")
PROFILE_TEAM_ID=$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$PROVISIONING_PROFILE_PLIST_PATH")
if PROFILE_APP_IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$PROVISIONING_PROFILE_PLIST_PATH" 2>/dev/null); then
  :
elif PROFILE_APP_IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$PROVISIONING_PROFILE_PLIST_PATH" 2>/dev/null); then
  :
else
  echo "Provisioning profile does not contain an application identifier entitlement" >&2
  exit 1
fi

test "$PROFILE_TEAM_ID" = "$EXPECTED_TEAM_ID"
test "$PROFILE_APP_IDENTIFIER" = "$EXPECTED_TEAM_ID.$EXPECTED_BUNDLE_ID"

security create-keychain -p "$MACOS_KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$MACOS_KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERT_PATH" -k "$KEYCHAIN_PATH" -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/xcodebuild
security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -F "Developer ID Application:" | grep -F "($EXPECTED_TEAM_ID)"

PROFILE_INSTALL_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILE_INSTALL_DIR"
cp "$PROVISIONING_PROFILE_PATH" "$PROFILE_INSTALL_DIR/$PROFILE_UUID.provisionprofile"

security list-keychains -d user -s "$KEYCHAIN_PATH"
security default-keychain -d user -s "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple: -s -k "$MACOS_KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

echo "KEYCHAIN_PATH=$KEYCHAIN_PATH" >> "$GITHUB_ENV"
echo "APPSTORE_CONNECT_API_KEY_PATH=$API_KEY_PATH" >> "$GITHUB_ENV"
echo "PROVISIONING_PROFILE_UUID=$PROFILE_UUID" >> "$GITHUB_ENV"
