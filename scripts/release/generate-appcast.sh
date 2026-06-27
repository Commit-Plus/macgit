#!/bin/zsh
set -euo pipefail

TAG_NAME="${1:?usage: generate-appcast.sh <tag-name> <zip-name> <zip-path> <output-appcast>}"
ZIP_NAME="${2:?usage: generate-appcast.sh <tag-name> <zip-name> <zip-path> <output-appcast>}"
ZIP_PATH="${3:?usage: generate-appcast.sh <tag-name> <zip-name> <zip-path> <output-appcast>}"
OUTPUT_APPCAST="${4:?usage: generate-appcast.sh <tag-name> <zip-name> <zip-path> <output-appcast>}"

: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${SPARKLE_ED25519_PRIVATE_KEY:?SPARKLE_ED25519_PRIVATE_KEY is required}"

SPARKLE_CHECKOUT="$RUNNER_TEMP/SourcePackages/checkouts/Sparkle"
SPARKLE_BUILD_DIR="$RUNNER_TEMP/SourcePackages/sparkle-build"
APPCAST_WORK_DIR="$RUNNER_TEMP/appcast-work"
PRIVATE_KEY_PATH="$RUNNER_TEMP/sparkle_private_ed25519.pem"
DOWNLOAD_PREFIX="https://github.com/${GITHUB_REPOSITORY}/releases/download/${TAG_NAME}/"

test -d "$SPARKLE_CHECKOUT"

rm -rf "$SPARKLE_BUILD_DIR" "$APPCAST_WORK_DIR"
mkdir -p "$SPARKLE_BUILD_DIR" "$APPCAST_WORK_DIR"

cp "$ZIP_PATH" "$APPCAST_WORK_DIR/$ZIP_NAME"
printf '%s\n' "$SPARKLE_ED25519_PRIVATE_KEY" > "$PRIVATE_KEY_PATH"

swift build \
  --package-path "$SPARKLE_CHECKOUT" \
  --scratch-path "$SPARKLE_BUILD_DIR" \
  -c release \
  --product generate_appcast

"$SPARKLE_BUILD_DIR/release/generate_appcast" \
  --ed-key-file "$PRIVATE_KEY_PATH" \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  -o "$OUTPUT_APPCAST" \
  "$APPCAST_WORK_DIR"
