#!/bin/zsh
#  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
#  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU Affero General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU Affero General Public License for more details.
#
#  You should have received a copy of the GNU Affero General Public License
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.

set -euo pipefail

DMG_PATH="${1:?usage: notarize-dmg.sh <dmg-path>}"

: "${KEYCHAIN_PATH:?KEYCHAIN_PATH is required}"
: "${APPSTORE_CONNECT_API_KEY_PATH:?APPSTORE_CONNECT_API_KEY_PATH is required}"
: "${APPSTORE_CONNECT_KEY_ID:?APPSTORE_CONNECT_KEY_ID is required}"
: "${APPSTORE_CONNECT_ISSUER_ID:?APPSTORE_CONNECT_ISSUER_ID is required}"

test -f "$DMG_PATH"
test -f "$KEYCHAIN_PATH"

SIGNING_IDENTITY=$(
  security find-identity -v -p codesigning "$KEYCHAIN_PATH" |
    awk '/"Developer ID Application:/ && !identity { identity=$2 } END { print identity }'
)

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "No Developer ID Application signing identity found in $KEYCHAIN_PATH" >&2
  exit 1
fi

codesign --force \
  --sign "$SIGNING_IDENTITY" \
  --keychain "$KEYCHAIN_PATH" \
  --timestamp \
  "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

SUBMISSION_RESULT_PATH="${RUNNER_TEMP:-/tmp}/dmg-notary-submission.json"
NOTARY_LOG_PATH="${RUNNER_TEMP:-/tmp}/dmg-notary-log.json"

xcrun notarytool submit "$DMG_PATH" \
  --key "$APPSTORE_CONNECT_API_KEY_PATH" \
  --key-id "$APPSTORE_CONNECT_KEY_ID" \
  --issuer "$APPSTORE_CONNECT_ISSUER_ID" \
  --wait \
  --output-format json | tee "$SUBMISSION_RESULT_PATH"

SUBMISSION_ID=$(plutil -extract id raw "$SUBMISSION_RESULT_PATH")
SUBMISSION_STATUS=$(plutil -extract status raw "$SUBMISSION_RESULT_PATH")

if [[ "$SUBMISSION_STATUS" != "Accepted" ]]; then
  echo "DMG notarization failed with status: $SUBMISSION_STATUS" >&2
  xcrun notarytool log "$SUBMISSION_ID" \
    --key "$APPSTORE_CONNECT_API_KEY_PATH" \
    --key-id "$APPSTORE_CONNECT_KEY_ID" \
    --issuer "$APPSTORE_CONNECT_ISSUER_ID" \
    "$NOTARY_LOG_PATH"
  cat "$NOTARY_LOG_PATH"
  exit 1
fi

xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
