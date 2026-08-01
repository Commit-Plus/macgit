# Provider Connections Local-First Phase 1

**Branch:** `codex/provider-connections-local-first`

## Tasks

- [completed] Add a UserDefaults-backed local provider-account metadata store and a local-first store that optionally mirrors to Firestore.
- [completed] Keep controller accounts loaded across Firebase sign-out and use a stable machine-local owner identity for guest-created connections.
- [completed] Allow Add/Edit/Delete in Connections while signed out and present sign-in as optional sync affordance.
- [completed] Route Push after commit through MainWindow provider credential selection; preserve system credential-helper fallback when no app connection matches.
- [completed] Add focused storage/controller/presentation tests, run `git diff --check`, targeted XCTest, and macOS build.

## Verification

- Signed-out launch loads local connections.
- Guest OAuth/SSH connection saves locally and is immediately usable.
- Sign-in merges cloud metadata without dropping local connections.
- Sign-out leaves local connections visible and usable.
- Cloud load/save/delete failures do not roll back local state.
- Existing Keychain and SSH-key boundaries remain intact.
- Push after commit uses the same resolver as other push actions.

## Result

- Focused XCTest passed for 36 tests across local/cloud reconciliation, controller lifecycle, and Connections presentation.
- `git diff --check` passed.
- macOS build passed on the completed implementation.
