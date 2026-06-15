# Hybrid Git Runtime

**Date:** 2026-06-15
**Status:** Approved

## Overview

Add a hybrid Git runtime strategy so Commit+ can work for users who have never installed the Git CLI, without increasing the app bundle size. The app should check Git availability immediately on first launch. If no valid system Git is available, it downloads and installs a Git runtime managed privately by Commit+.

## Motivation

Commit+ currently shells out to `git` through `GitStatusService`. This keeps the implementation simple, but it means repository features fail when Git is missing. Bundling Git inside the app would avoid that failure but would make every app download heavier, including for users who already have Git installed.

The desired behavior is:

- Users with Git installed keep using their existing Git.
- Users without Git get an automatic first-launch setup.
- The app does not install or modify Git globally.
- The initial app bundle remains lightweight.

## Architecture

### GitRuntimeManager

Introduce a new runtime resolver responsible for finding, installing, and validating Git:

```swift
actor GitRuntimeManager {
    static let shared = GitRuntimeManager()

    func availability() async -> GitRuntimeAvailability
    func executableURL() async throws -> URL
    func installManagedRuntime() async throws
}
```

`GitRuntimeManager` owns the resolution order:

1. Valid system Git discovered from the user's environment.
2. Valid managed Git already installed by Commit+.
3. Missing Git, requiring first-launch setup.

Validation should run `git --version` rather than only checking whether a file exists.

### Runtime State

Use a small enum to drive startup UI:

```swift
enum GitRuntimeAvailability: Equatable {
    case ready(GitRuntimeSource)
    case missing
    case installing(progress: Double?)
    case failed(String)
}

enum GitRuntimeSource: Equatable {
    case system(URL)
    case managed(URL)
}
```

### Storage

Managed Git should live under app-private Application Support:

```text
~/Library/Application Support/Commit+/Git/<version>/
```

The app should maintain a stable `current` marker or metadata file so future releases can install a newer runtime without destroying the old one until the new runtime validates successfully.

### Download Manifest

The app should not download an ambiguous latest build. It should use a pinned manifest controlled by the app release or by a trusted app-owned endpoint:

```json
{
  "version": "2.x.y",
  "platform": "macos-universal",
  "url": "https://...",
  "sha256": "...",
  "archiveSize": 12345678
}
```

The installer must verify the SHA-256 checksum before extraction. A failed checksum is treated as an installation failure and the downloaded archive is deleted.

## Startup Flow

When the app launches:

1. `ContentView` or an app-level runtime gate starts `GitRuntimeManager.availability()`.
2. If system Git is valid, the app proceeds immediately.
3. If managed Git is valid, the app proceeds immediately.
4. If Git is missing, the app shows a setup screen and starts the managed runtime install.
5. After install, the app validates `git --version`.
6. Once validation succeeds, normal app UI becomes available.

This should happen before the user opens or clones a repository, because first launch is the moment when internet access is most likely available.

## GitStatusService Integration

Replace the current `gitExecutable()` path lookup in `GitStatusService` with `GitRuntimeManager.shared.executableURL()`:

```swift
let executable = try await GitRuntimeManager.shared.executableURL()
task.executableURL = executable
```

All existing Git commands can keep using `runGit(arguments:in:)`. This keeps the change contained and avoids rewriting status, diff, branch, remote, commit, stash, and history logic.

`applyPatch` should use the same resolver instead of calling the old `gitExecutable()` helper.

## UI Design

If Git is missing on first launch, show a setup state before the repo picker:

- Title: `Setting up Git for Commit+`
- Progress states: checking, downloading, installing, validating
- Retry action if download or validation fails
- Manual fallback action that points users to Git installation instructions

The setup UI should be quiet and direct. It should not ask the user to install Xcode Command Line Tools unless the managed runtime installation fails or the user chooses manual setup.

## Error Handling

| Scenario | Behavior |
|----------|----------|
| System Git exists and validates | Use system Git |
| System Git path exists but `git --version` fails | Ignore it and try managed Git |
| Managed Git exists and validates | Use managed Git |
| No Git exists | Start first-launch managed install |
| Download fails | Show retry and manual install fallback |
| Checksum fails | Delete archive, show retry |
| Extraction fails | Show retry |
| Runtime validates after install | Continue to normal app UI |

`GitError.gitNotFound` should become a final fallback. In normal operation, users should see the first-launch setup UI before any repository action can hit that error.

## Security and Maintenance

- Verify downloads with SHA-256 before extraction.
- Prefer HTTPS-only download URLs.
- Keep runtime updates pinned to an explicit version.
- Install new runtime versions side by side, validate them, then switch the active runtime.
- Do not mutate global PATH, `/usr/local/bin`, Homebrew, or Xcode Command Line Tools.

## Testing

- Launch with system Git available: app should proceed without downloading.
- Launch with `PATH` hiding Git and no managed runtime: setup UI should install managed Git.
- Launch with managed Git already installed: app should proceed without downloading.
- Corrupt downloaded archive: checksum failure should delete the archive and allow retry.
- Broken managed runtime: app should reinstall or show retry rather than crashing.
- Existing Git workflows should still pass through `GitStatusService.runGit`.

## Future Work

- Add a runtime update check after app launch.
- Support separate arm64 and x86_64 packages if universal builds are too large.
- Add telemetry-free local diagnostics for runtime source and version.
