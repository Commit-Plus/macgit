# Repository Bookmarks Roadmap

**Goal:** Let users bookmark remote repositories, sync bookmark metadata through Firebase, and restore each bookmark on another Mac by cloning it or linking an existing local folder.

**Architecture:** A shared bookmark controller keeps an immediate local cache and observes a user-owned Firestore collection while signed in. Cloud documents contain only machine-independent remote identity metadata. Local repository paths remain in `UserDefaults` and are reconciled against canonical remotes.

**Tech Stack:** Swift, SwiftUI, Combine, FirebaseFirestore, XCTest, Firestore Emulator.

## Plan

- [completed] Phase 1 — Add bookmark identity/model, local cache, cloud-store boundary, Firestore adapter, rules, and focused tests.
- [completed] Phase 2 — Integrate bookmark rows, one-click filtering, clone prefill, and verified folder linking into `RepoPickerView`.
- [completed] Phase 3 — Firestore emulator rules passed 15 tests, `git diff --check` passed, and the macOS build succeeded. Focused XCTest execution remains blocked by pre-existing async-autoclosure compile errors in `GitRuntimeManagerTests`.

## Shared Rules

- Never upload local filesystem paths, credentials, branch state, or working-copy counts.
- Identify a repository by its normalized remote host and owner/repository path.
- Keep guest behavior functional; bookmark changes remain local while signed out and sync after sign-in.
- Treat “not linked on this Mac” separately from “previously linked folder moved or deleted.”
- Validate a selected link folder against the bookmark’s canonical remote before saving the mapping.
- Do not launch the app during verification.

## Out of Scope

- Syncing the Recent Repositories list or `lastOpened`.
- Provider API enrichment such as avatars, descriptions, stars, or default branches.
- Bookmarking repositories without a usable Git remote.
