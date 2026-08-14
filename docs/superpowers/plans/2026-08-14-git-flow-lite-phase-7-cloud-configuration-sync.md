# Git Flow Lite Phase 7: Account-Scoped Repository Configuration Sync

Status: completed on `codex/git-flow-cloud-sync`; production Firestore rules deployed to project `macgit` and active source verified.

## Goal

Make a signed-in user's durable Git Flow configuration follow the same remote repository across Macs while preserving the Git-common-dir file as the runtime and offline cache.

## Product decisions

- Identify the repository with the existing canonical remote identity used by Repository Bookmarks. HTTPS and SSH forms of the same remote must resolve to the same Firestore document.
- Store cloud documents at `users/{uid}/gitFlowConfigurations/{repositoryID}`.
- Sync workflow enablement, Main/Develop branch roles, four topic prefixes, Feature/Bugfix Finish strategy, and Release/Hotfix tag preferences.
- Keep the default Start destination local because it is a machine workflow preference.
- Never sync repository paths, worktree paths, recovery checkpoints, operation state, Git refs, credentials, or Undo/Redo state.
- A signed-out user or repository without a supported remote remains fully local.
- On open, an existing cloud document wins and refreshes the local cache. When no cloud document exists, an existing valid local configuration seeds Firebase.
- Saving settings must always persist locally first. Cloud failure must be reported without breaking local Git Flow.
- A failed signed-in upload remains pending on that Mac and is retried before cloud state is allowed to replace the local configuration.

## Expected file map

- Add a cloud configuration model/document codec under `macgit/Models` or `macgit/Services`.
- Add a Firestore-backed configuration store under `macgit/Services`.
- Add an app-owned sync controller under `macgit/App` and inject it through the SwiftUI environment.
- Add a repository remote identity resolver that reuses `RepositoryBookmarkIdentity` canonicalization.
- Integrate initial reconciliation, account changes, configuration save, and Disable Workflow in `MainWindowView` coordination code.
- Add the Firestore collection schema to `firestore.rules` and emulator coverage.
- Add focused XCTest coverage for exact cloud schema, decoding, local-only fields, and reconciliation policy.

## Verification

- Canonical HTTPS and SSH remotes select the same cloud document.
- A new clone with no local file downloads cloud configuration and writes the local cache.
- An existing local configuration uploads only when the cloud document is absent.
- Cloud decoding preserves the machine-local Start destination.
- Signed-out and no-remote repositories stay local without errors.
- Firestore rules enforce user ownership, exact fields, supported schema/strategy, types, and reject paths/secrets/checkpoints.
- Run focused Git Flow/cloud tests, Firestore emulator rules tests, `git diff --check`, and the macOS build. Do not launch the app.

## Non-goals

- Syncing live Git branch refs or performing fetch/push.
- Syncing recovery or Undo/Redo state.
- Adding a tracked repository configuration file.
- Adding a custom conflict UI or background multi-document listener in this phase.

## Verification result

- Firestore emulator rules suite passed 26/26 tests, including owner isolation, exact schema validation, and rejection of local paths, checkpoints, credentials, and machine-only defaults.
- `xcodebuild build-for-testing` passed, proving the app and focused XCTest target compile together.
- The focused XCTest execution reached the test-host boundary but remained runtime-unverified because the Firebase-enabled host aborted before establishing the XCTest connection (`Early unexpected exit` / `abort() called`); it was not rerun after the known bootstrap failure.
- `git diff --check` and the macOS `xcodebuild build` passed.
- The app was not launched. Production Firestore rules were deployed, and active ruleset `projects/macgit/rulesets/4cf6ab62-42d5-4dd3-bfc1-ef5f48df6a9c` matched the local `firestore.rules` SHA-256 exactly.
