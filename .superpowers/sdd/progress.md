# Submodule/Subtree Phase 5 SDD Progress

Branch base: `75dc083010f77796e7e807a141165a6e562f57ed`
Plan: `docs/superpowers/plans/2026-07-13-submodule-subtree-phase-5-subtree-operations.md`

## Task 1 - Capability and Clean-Tree Policy

- Implemented `SubtreeOperation`, `SubtreeOperationDecision`, and `SubtreeOperationPolicy`.
- Added `GitStatusService.supportsGitSubtree(in:)` and `subtreeOperationDecision(in:)`.
- Covered usage-output capability success, missing subtree failure, clean tree, dirty status records, conflicts, untracked files, and deterministic blocking path parsing.
- Verification: `rtk xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitSubtreeCapabilityTests -only-testing:macgitTests/SubtreeOperationPolicyTests` passed.
- Review fix: `subtreeOperationDecision(in:)` now checks `git subtree -h` before status and returns the unavailable message when the helper is missing.

## Task 2 - Subtree Network Operations

- Implemented `addSubtree`, `pullSubtree`, and `pushSubtree` on `GitStatusService`.
- Add validates the clean parent, normalizes the new prefix, injects credentials through the existing remote credential path, runs `git subtree add`, saves the subtree registry only after command success, and posts `.repositoryDidChange` after save.
- Pull and push reuse the same clean-tree and credential preflight, run `git subtree pull/push`, and refresh observers only after success.
- Added local bare-repository integration coverage for add without squash, add with squash, pull, and push.
- Added recording-runner coverage for missing capability, dirty parent rejection, command failure without registry save/notification, and successful add save/notification ordering.
- Verification: `rtk xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitSubtreeCapabilityTests -only-testing:macgitTests/SubtreeOperationPolicyTests -only-testing:macgitTests/GitSubtreeOperationTests` passed.

## Task 3 - Add/Pull/Push UI

- Enabled Add New in `AddLinkSubtreeSheet`, defaulting to Add New and `Squash imported history`.
- Routed Add through `GitStatusService.addSubtree` with provider credentials and the progress label `Adding subtree...`.
- Added folder-gated subtree row actions `Pull from Subtree Remote...` and `Push to Subtree Remote...`.
- Added MainWindow-owned pull/push confirmation sheets with repository, branch, prefix, squash policy, credential-aware service calls, and inline recoverable errors.
- Added a dirty-tree preflight message that lists up to five blocking paths with a remaining-count suffix before running the subtree operation.
- Extended subtree operation coverage for credential environment injection without token-bearing git arguments.
- Verification: `rtk xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' -only-testing:macgitTests/GitSubtreeCapabilityTests -only-testing:macgitTests/GitSubtreeOperationTests -only-testing:macgitTests/SubtreeOperationPolicyTests -only-testing:macgitTests/SubtreeSidebarPolicyTests -only-testing:macgitTests/GitCredentialInjectorTests` passed.

## Task 4 - Verification and Remaining Handoff

- Full-suite attempt: `rtk xcodebuild test -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS'` exited 65 with the documented test-host bootstrap abort: `Early unexpected exit` / `abort() called`. Per repo guidance, it was not rerun.
- Build verification: `rtk xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build` passed.
- Updated the phase plan and roadmap to show Phase 5 implementation in progress with manual QA and merge still pending.
