# Personal Changes Phase 5: Portable Export and Import

**Branch:** `codex/personal-changes-phase-5-portability`

**Goal:** Let a user deliberately transfer stable Personal Change profiles between Macs using a validated portable package, without syncing local paths, credentials, worktree state, or mutable cloud state.

**Architecture:** Export produces a versioned Finder package named `*.commitplus-personal-changes` containing normalized profile manifests, patch payloads, canonical repository identity when available, and checksums. Import is preview-first and non-mutating until repository identity, schema, eligibility, duplicate, and conflict decisions pass. The local Phase 4 store remains authoritative.

## Prerequisites

- Phase 4 is merged and the persisted profile schema is considered stable for external interchange.
- Start from clean, updated `main`.
- Confirm current repository canonical-remote identity behavior in `RepositoryBookmarkIdentity`/`GitRemoteIdentityResolver` and current macOS file importer/exporter conventions.
- Approve the package extension and user-facing warning that exported patches contain source code in plaintext.

## Package Contract

```text
Local Development.commitplus-personal-changes/
  manifest.json
  checksums.json
  profiles/
    <profile-uuid>/
      manifest.json
      changes.patch
```

The package is a directory bundle presented as one document in Finder. It contains repository-relative file paths because patches require them, but never an absolute local path.

## Tasks

### Task 1: Define and test the portable schema

**Files:**

- Create: `macgit/Models/PersonalChangePackage.swift`
- Create: `macgit/Services/PersonalChangePackageCodec.swift`
- Test: `macgitTests/PersonalChangePackageCodecTests.swift`

- [ ] Add an independent package schema version and minimum reader version.
- [ ] Include export timestamp, Commit+ format version, optional canonical repository key/remote metadata, profiles, payload checksums, and no device-local working state.
- [ ] Normalize line endings and JSON ordering before checksum generation.
- [ ] Reject path traversal, absolute paths, symlink payloads, duplicate IDs/paths, checksum mismatch, unknown mandatory fields, and unsupported schema.
- [ ] Verify package contents never include repository root path, username, credentials, Firebase UID, device name, applied state, or temporary paths.
- [ ] Round-trip Unicode profile names, multiple profiles, multiple files, branch scope, and empty optional repository identity.

### Task 2: Implement safe export

**Files:**

- Create: `macgit/Services/PersonalChangeExportService.swift`
- Modify: `macgit/App/PersonalChangesController.swift`
- Modify: `macgit/Views/PersonalChanges/PersonalChangeDetailView.swift`
- Create: `macgit/Views/PersonalChanges/PersonalChangeExportSheet.swift`
- Test: `macgitTests/PersonalChangeExportTests.swift`

- [ ] Export selected profiles from persisted definitions, not by re-reading and accidentally absorbing current working changes.
- [ ] Resolve canonical repository identity from supported remotes when available.
- [ ] Write the complete package to a temporary sibling and move it into the user-selected destination only after checksums validate.
- [ ] Warn clearly that the package contains plaintext source patches and should be handled like source code.
- [ ] Export is read-only with respect to profiles, index, and working files.
- [ ] Support replacing an existing package only through the native save-panel confirmation.

### Task 3: Implement preview-first import and repository validation

**Files:**

- Create: `macgit/Services/PersonalChangeImportPlanner.swift`
- Create: `macgit/Views/PersonalChanges/PersonalChangeImportSheet.swift`
- Modify: `macgit/App/PersonalChangesController.swift`
- Modify: `macgit/Views/MainWindow/Sidebar/SidebarPersonalChangesSection.swift`
- Test: `macgitTests/PersonalChangeImportPlannerTests.swift`
- Test: `macgitTests/PersonalChangeImportIntegrationTests.swift`

- [ ] Parse and validate the complete package before presenting import choices.
- [ ] Compare canonical repository identity when both package and destination have one.
- [ ] Block an identity mismatch by default; permit explicit import to a different repository only after showing every relative path and confirming they exist/are eligible.
- [ ] For remote-less repositories, require explicit destination confirmation.
- [ ] Preview profile names, scopes, files, conflicts, unsupported entries, and whether each patch is currently Applied, Paused, or Needs Attention.
- [ ] Import profiles as Paused definitions by default. Applying after import is a separate explicit action.
- [ ] Never write working files or index during package import.

### Task 4: Resolve duplicates without automatic merge

**Files:**

- Modify: `macgit/Services/PersonalChangeImportPlanner.swift`
- Modify: `macgit/Views/PersonalChanges/PersonalChangeImportSheet.swift`
- Test: `macgitTests/PersonalChangeImportConflictTests.swift`

- [ ] Match exact identity by profile UUID and exact payload by checksum.
- [ ] Skip exact duplicates safely.
- [ ] For same UUID with different content, offer Keep Existing, Import as Copy with a new UUID, Replace Stored Definition, or Cancel.
- [ ] Replace Stored Definition never applies/reverses a patch and is disabled when doing so would orphan an Applied current definition without explicit acknowledgment.
- [ ] Profiles with different UUIDs but overlapping protected hunks are imported disabled/unprotected or blocked pending explicit ownership resolution; never silently merge patches.
- [ ] Perform all selected definition writes atomically or leave the store unchanged.

### Task 5: Verify portability and close the roadmap

- [ ] Test export on repository A, transfer the package path, import into a fresh clone B, then explicitly Apply and verify the expected working diff.
- [ ] Test mismatched remotes, no remotes, changed base content, duplicate UUIDs, tampered checksums, path traversal, partial package writes, and imported Needs Attention state.
- [ ] Run all package tests, relevant Phase 1–4 tests, `rtk git diff --check`, and the macOS build sequentially.
- [ ] Do not launch the app; record native save/open panel lifecycle and Finder package presentation as manual runtime acceptance.
- [ ] Merge to `main`, then mark Phase 5 and the top-level roadmap `[completed]`.

## Acceptance Criteria

- A profile exported on one Mac can be imported into a clean clone on another Mac and explicitly applied to reproduce the saved personal diff.
- Export/import never mutates working files or index on its own.
- Packages contain relative patch paths but no absolute paths, credentials, device/account identifiers, or applied worktree state.
- Repository identity mismatch, corruption, unsupported schema, duplicate identity, and overlapping ownership are visible before any write.
- Import is atomic and defaults to Paused.
- The package warns that it contains plaintext source code.

## Explicit Non-Goals

- No automatic discovery or transfer between Macs.
- No Firebase, object storage, background sync, tombstones, or concurrent-device merge.
- No encryption or password-protected package in this phase.
- No team sharing or remote repository publication.
- No automatic Apply immediately after import.

