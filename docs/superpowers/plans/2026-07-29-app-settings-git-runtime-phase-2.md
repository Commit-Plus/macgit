# App Settings Git Runtime Phase 2

**Status:** completed

## Scope

- Preserve Automatic mode, which prefers a valid system Git and falls back to
  an installed embedded runtime.
- Allow users to explicitly select System Git or Embedded Git.
- Show the detected path and version for both runtimes.
- Offer a Download button when Embedded Git is not installed.
- Verify the pinned archive checksum before installing it under Commit+'s
  Application Support directory.
- Route every Git command through the selected runtime.

## Runtime Source

Commit+ uses pinned macOS arm64 and x64 archives from GitHub Desktop's
`desktop/dugite-native` release. The archive URL and SHA-256 are compiled into
the app, so installation does not depend on an ambiguous latest release.

## Boundaries

- Runtime preference and installation are local to this Mac and are not synced
  through Firebase.
- Commit+ does not modify the system Git installation or global `PATH`.
- Download progress is indeterminate in this phase.

## Verification

- Focused resolver tests cover preference priority, missing runtimes, checksum
  validation, and the Embedded Git execution environment. The test source
  compiles; execution is blocked by the existing `RepoPickerViewTests`
  missing-count-arguments failure.
- The pinned arm64 archive was downloaded independently, matched its expected
  size and SHA-256, and successfully ran `git --version`, `git init`, and
  `git status` from a temporary extraction.
- `git diff --check` passes.
- The macOS app builds successfully without launching it.
