# Submodule/Subtree Phase 5 SDD Progress

Branch base: `75dc083010f77796e7e807a141165a6e562f57ed`
Plan: `docs/superpowers/plans/2026-07-13-submodule-subtree-phase-5-subtree-operations.md`

## Task 1 - Capability and Clean-Tree Policy

- Implemented `SubtreeOperation`, `SubtreeOperationDecision`, and `SubtreeOperationPolicy`.
- Added `GitStatusService.supportsGitSubtree(in:)` and `subtreeOperationDecision(in:)`.
- Covered usage-output capability success, missing subtree failure, clean tree, dirty status records, conflicts, untracked files, and deterministic blocking path parsing.
- Verification: `rtk xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitSubtreeCapabilityTests -only-testing:macgitTests/SubtreeOperationPolicyTests` passed.
