# App Settings Git Phase 1

**Status:** completed

## Scope

- Show the resolved Git executable and version.
- Read and update global author name and email.
- Read and update `init.defaultBranch`, `fetch.prune`, and `push.autoSetupRemote`.
- Read, choose, create, and open the global ignore file.
- Open the global Git configuration file.
- Preserve explicit Save semantics and surface loading, success, and error states.

## Architecture

- `GitSettingsView` renders controls and callbacks only.
- `GitSettingsViewModel` owns loading, drafts, validation, save state, and file-opening actions.
- `GitStatusService` owns all `git config --global` reads and writes.

## Verification

- Focused service tests use `GitCommandRunning`. The new test source compiles, but
  targeted test execution is currently blocked by the existing missing
  `commitCount`, `pullCount`, and `pushCount` arguments in
  `RepoPickerViewTests`.
- `git diff --check` passes.
- The macOS app builds successfully without launching it.
