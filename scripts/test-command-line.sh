#!/bin/bash
set -euo pipefail
cli_root="$(cd "$(dirname "$0")/.." && pwd)"
cli_test_dir="$(mktemp -d)"
trap 'rm -rf "$cli_test_dir"' EXIT
cli_sources=()
while IFS= read -r cli_source; do
  case "$cli_source" in
    *.swift)
      [[ "$cli_source" == *CommitCommand.swift ]] && continue
      cli_sources+=("$cli_root/${cli_source#*/}")
      ;;
  esac
done < "$cli_root/command-line/inputs.xcfilelist"
xcrun swiftc -parse-as-library -swift-version 5 \
  "${cli_sources[@]}" "$cli_root/macgit/Services/CommandLineInstaller.swift" \
  "$cli_root/macgit/Services/CommandLineShellConfiguration.swift" \
  "$cli_root/macgit/Services/CommandLineReminderPolicy.swift" \
  "$cli_root/macgit/ViewModels/CommandLineSetupModel.swift" \
  "$cli_root/command-line/Tests.swift" -o "$cli_test_dir/tests"
"$cli_test_dir/tests"
