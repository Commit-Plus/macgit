# Submodule/Subtree Phase 4 SDD Progress

Branch base: `43db81e0606f616404627300df1ecf4d7bb020bb`
Plan: `docs/superpowers/plans/2026-07-13-submodule-subtree-phase-4-subtree-registry.md`

## Task 1 - Local Subtree Registry

- Implemented `GitSubtreeEntry` and `GitSubtreeRegistry`.
- Covered empty reads, round-trip storage, deterministic path ordering, stable ID suffixing, incomplete entry omission, duplicate/overlap rejection, stale folder reads, edits, and removal.
- Verification: `rtk xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitSubtreeRegistryTests` passed.

## Task 2 - Link Existing Subtrees

- Implemented `SubtreeLinkRequest` and `GitStatusService.linkExistingSubtree`.
- Validates required fields, relative/non-escaping paths, symlink escapes, existing directory, tracked content, duplicate/overlapping registry paths, and notification timing after metadata save.
- Verification: `rtk xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitSubtreeRegistryTests -only-testing:macgitTests/SubtreeLinkValidationTests` passed.
