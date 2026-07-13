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

DMG_PATH="${1:?usage: verify-dmg.sh <dmg-path>}"

: "${RUNNER_TEMP:?RUNNER_TEMP is required}"

test -f "$DMG_PATH"

MOUNT_POINT="$RUNNER_TEMP/CommitPlusDMGVerify"
ATTACH_PLIST="$RUNNER_TEMP/CommitPlusDMGAttach.plist"
DEVICE=""

cleanup() {
  if [[ -n "$DEVICE" ]]; then
    hdiutil detach "$DEVICE" >/dev/null 2>&1 || true
  fi
  rm -rf "$MOUNT_POINT" "$ATTACH_PLIST"
}
trap cleanup EXIT

rm -rf "$MOUNT_POINT" "$ATTACH_PLIST"
mkdir -p "$MOUNT_POINT"

hdiutil attach "$DMG_PATH" \
  -nobrowse \
  -readonly \
  -mountpoint "$MOUNT_POINT" \
  -plist > "$ATTACH_PLIST"

DEVICE=$(/usr/libexec/PlistBuddy -c 'Print :system-entities:0:dev-entry' "$ATTACH_PLIST")

test -d "$MOUNT_POINT/Commit+.app"
test -L "$MOUNT_POINT/Applications"
test "$(readlink "$MOUNT_POINT/Applications")" = "/Applications"

codesign --verify --deep --strict --verbose=2 "$MOUNT_POINT/Commit+.app"
spctl --assess --type execute --verbose "$MOUNT_POINT/Commit+.app"
codesign --verify --verbose=2 "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH"
hdiutil verify "$DMG_PATH"
