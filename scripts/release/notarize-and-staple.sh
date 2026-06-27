#!/bin/zsh
set -euo pipefail

ZIP_PATH="${1:?usage: notarize-and-staple.sh <zip-path> <app-path>}"
APP_PATH="${2:?usage: notarize-and-staple.sh <zip-path> <app-path>}"

: "${APPSTORE_CONNECT_API_KEY_PATH:?APPSTORE_CONNECT_API_KEY_PATH is required}"
: "${APPSTORE_CONNECT_KEY_ID:?APPSTORE_CONNECT_KEY_ID is required}"
: "${APPSTORE_CONNECT_ISSUER_ID:?APPSTORE_CONNECT_ISSUER_ID is required}"

xcrun notarytool submit "$ZIP_PATH" \
  --key "$APPSTORE_CONNECT_API_KEY_PATH" \
  --key-id "$APPSTORE_CONNECT_KEY_ID" \
  --issuer "$APPSTORE_CONNECT_ISSUER_ID" \
  --wait

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
