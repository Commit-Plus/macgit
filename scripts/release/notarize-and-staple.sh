#!/bin/zsh
set -euo pipefail

ZIP_PATH="${1:?usage: notarize-and-staple.sh <zip-path> <app-path>}"
APP_PATH="${2:?usage: notarize-and-staple.sh <zip-path> <app-path>}"

: "${APPSTORE_CONNECT_API_KEY_PATH:?APPSTORE_CONNECT_API_KEY_PATH is required}"
: "${APPSTORE_CONNECT_KEY_ID:?APPSTORE_CONNECT_KEY_ID is required}"
: "${APPSTORE_CONNECT_ISSUER_ID:?APPSTORE_CONNECT_ISSUER_ID is required}"

SUBMISSION_RESULT_PATH="${RUNNER_TEMP:-/tmp}/notary-submission.json"
NOTARY_LOG_PATH="${RUNNER_TEMP:-/tmp}/notary-log.json"

xcrun notarytool submit "$ZIP_PATH" \
  --key "$APPSTORE_CONNECT_API_KEY_PATH" \
  --key-id "$APPSTORE_CONNECT_KEY_ID" \
  --issuer "$APPSTORE_CONNECT_ISSUER_ID" \
  --wait \
  --output-format json | tee "$SUBMISSION_RESULT_PATH"

SUBMISSION_ID=$(plutil -extract id raw "$SUBMISSION_RESULT_PATH")
SUBMISSION_STATUS=$(plutil -extract status raw "$SUBMISSION_RESULT_PATH")

if [[ "$SUBMISSION_STATUS" != "Accepted" ]]; then
  echo "Notarization failed with status: $SUBMISSION_STATUS" >&2
  xcrun notarytool log "$SUBMISSION_ID" \
    --key "$APPSTORE_CONNECT_API_KEY_PATH" \
    --key-id "$APPSTORE_CONNECT_KEY_ID" \
    --issuer "$APPSTORE_CONNECT_ISSUER_ID" \
    "$NOTARY_LOG_PATH"
  cat "$NOTARY_LOG_PATH"
  exit 1
fi

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
