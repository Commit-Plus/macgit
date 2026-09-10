#!/bin/bash
set -euo pipefail

cli_work="$DERIVED_FILE_DIR/CommitCLI"
cli_output="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers/commit"
mkdir -p "$cli_work" "$(dirname "$cli_output")"
cli_sources=(
  "$SRCROOT/command-line/CommitCommand.swift"
  "$SRCROOT/macgit/Services/RepositoryOpenRequest.swift"
  "$SRCROOT/macgit/Services/RepositoryOpenError.swift"
  "$SRCROOT/macgit/Services/RepositoryPathResolver.swift"
  "$SRCROOT/macgit/Services/GitRuntimeManager.swift"
  "$SRCROOT/macgit/Services/GitRuntimeManifest.swift"
  "$SRCROOT/macgit/Services/GitRuntimeError.swift"
  "$SRCROOT/macgit/Models/GitRuntimePreference.swift"
  "$SRCROOT/macgit/Models/GitRuntimeStatus.swift"
)
cli_binaries=()
for cli_arch in $ARCHS; do
  cli_binary="$cli_work/commit-$cli_arch"
  xcrun --sdk macosx swiftc -parse-as-library -swift-version 5 \
    -O -sdk "$SDKROOT" -target "$cli_arch-apple-macosx$MACOSX_DEPLOYMENT_TARGET" \
    -module-cache-path "$cli_work/ModuleCache" "${cli_sources[@]}" -o "$cli_binary"
  cli_binaries+=("$cli_binary")
done
xcrun lipo -create "${cli_binaries[@]}" -output "$cli_output"
if [[ "${CODE_SIGNING_ALLOWED:-NO}" == "YES" && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
  cli_sign_options=(--force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --options runtime)
  if [[ "$EXPANDED_CODE_SIGN_IDENTITY" != "-" ]]; then
    cli_sign_options+=(--timestamp)
  fi
  /usr/bin/codesign "${cli_sign_options[@]}" "$cli_output"
fi
