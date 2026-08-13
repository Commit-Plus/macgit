# Personal Changes Phase 1: Foundation and Patch Engine

**Branch:** `codex/personal-changes-phase-1-foundation`

**Goal:** Establish a versioned repository-local model and a tested patch engine that can capture, inspect, apply, and pause Personal Changes without any user-facing integration or staging protection.

**Architecture:** Pure models and policy types describe profiles, entries, eligibility, requests, and derived state. `PersonalChangeStore` persists profiles under the absolute Git common directory. `PersonalChangeService` coordinates validation and persistence; Git process execution remains in `GitStatusService` extensions. No SwiftUI view owns or reconstructs patch state.

## Prerequisites

- Start from clean, updated `main`.
- Create the phase branch exactly as described in the roadmap.
- Read the design and confirm the persisted schema and MVP eligibility have not been superseded.
- Record baseline focused status/diff/patch test results before changing production code.

## Tasks

### Task 1: Add the domain model and pure policies

**Files:**

- Create: `macgit/Models/PersonalChangeProfile.swift`
- Create: `macgit/Models/PersonalChangeState.swift`
- Create: `macgit/Models/PersonalChangeRequest.swift`
- Create: `macgit/Services/PersonalChangeEligibility.swift`
- Test: `macgitTests/PersonalChangeModelTests.swift`
- Test: `macgitTests/PersonalChangeEligibilityTests.swift`

- [ ] Define schema-versioned, Codable, Equatable, Sendable profile, entry, scope, and capture/apply/pause request types.
- [ ] Normalize profile names, branch names, paths, entry ordering, and duplicate entry IDs deterministically.
- [ ] Define entry and aggregate states without persisting a trusted Applied Boolean.
- [ ] Encode exact rejection reasons for untracked, staged-path, binary, rename, deletion, conflict, submodule, mode-only, detached-HEAD branch-scope, and overlapping-profile cases.
- [ ] Ensure requests passed into async work contain immutable copied values and do not capture mutable SwiftUI state.
- [ ] Unit-test round-trip coding, unsupported schema detection helpers, scope matching, state aggregation, normalization, and every MVP eligibility rejection.

### Task 2: Add an atomic Git-common-directory store

**Files:**

- Create: `macgit/Services/PersonalChangeStore.swift`
- Create: `macgit/Services/PersonalChangeStoreError.swift`
- Test: `macgitTests/PersonalChangeStoreTests.swift`

- [ ] Resolve storage from `GitStatusService.gitCommonDirectory(in:)`, never from `repositoryURL/.git` string concatenation.
- [ ] Store profiles beneath `<git-common-dir>/commitplus/personal-changes/profiles/<uuid>/` with a schema marker and deterministic manifest/patch payload.
- [ ] Write through a sibling temporary location and replace atomically only after all bytes are ready.
- [ ] Load healthy profiles even when one profile is corrupt; return a typed issue for each isolated invalid profile.
- [ ] Refuse to overwrite a schema newer than the app supports.
- [ ] Verify linked worktrees resolve the same definitions, while two unrelated repositories do not share profiles.
- [ ] Test missing directories, empty stores, corrupt manifests, corrupt patches, unsupported versions, interrupted temporary files, atomic replacement, and deletion that keeps working files unchanged.

### Task 3: Build capture and inspection primitives

**Files:**

- Create: `macgit/Services/PersonalChangePatchBuilder.swift`
- Create: `macgit/Services/PersonalChangeInspector.swift`
- Create: `macgit/Services/GitStatusService+PersonalChanges.swift`
- Modify only if required: `macgit/Services/GitCommandRunning.swift`
- Reuse where valid: `macgit/Services/DiffPatchBuilder.swift`
- Test: `macgitTests/PersonalChangePatchBuilderTests.swift`
- Test: `macgitTests/PersonalChangeInspectorTests.swift`

- [ ] Resolve the current index blob OID and file mode for every selected path.
- [ ] Build a patch from selected hunks/lines without absorbing unselected changes in the same file.
- [ ] Store stable patch fingerprints derived from normalized patch bytes, not `DiffLine.id` or hunk offsets alone.
- [ ] Validate forward application against the captured base and reverse application against the current working content.
- [ ] Inspect forward and reverse applicability per entry and aggregate Applied, Paused, Partially Applied, Needs Attention, Staged Externally, and Unavailable for Branch.
- [ ] Make inspection non-mutating and test that index, working files, and stored profiles remain byte-identical.
- [ ] Cover nearby ordinary edits, repeated context, whitespace changes, missing paths, changed base commits, partial application, and an unavailable base blob.

### Task 4: Implement transactional Capture, Apply, and Pause

**Files:**

- Create: `macgit/Services/PersonalChangeService.swift`
- Modify: `macgit/Services/GitStatusService+PersonalChanges.swift`
- Test: `macgitTests/PersonalChangeLifecycleIntegrationTests.swift`

- [ ] Capture with Keep Applied validates and persists the selected patch without writing the worktree or index.
- [ ] Capture with Save and Pause preflights the complete reverse, persists atomically, reverses once, and restores/removes the newly persisted definition if execution fails.
- [ ] Apply and Pause validate every entry before mutation and execute one complete patch only after all checks pass.
- [ ] Apply/Pause reject staged changes for affected paths in Phase 1 rather than guessing how to preserve them.
- [ ] Successful mutations refresh through the caller contract and post `.repositoryDidChange`; routine success remains silent.
- [ ] Failed mutations leave profile bytes, working files, and index unchanged.
- [ ] Use real temporary Git repositories to cover multi-file profiles, mixed personal/ordinary non-overlapping hunks, branch scope, linked worktrees, and patch conflicts.

### Task 5: Verify and close the phase

- [ ] Run focused tests sequentially:

  ```bash
  rtk xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' \
    -only-testing:macgitTests/PersonalChangeModelTests \
    -only-testing:macgitTests/PersonalChangeEligibilityTests \
    -only-testing:macgitTests/PersonalChangeStoreTests \
    -only-testing:macgitTests/PersonalChangePatchBuilderTests \
    -only-testing:macgitTests/PersonalChangeInspectorTests \
    -only-testing:macgitTests/PersonalChangeLifecycleIntegrationTests test
  rtk git diff --check
  rtk xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
  ```

- [ ] Do not launch the app.
- [ ] Commit the implementation on the phase branch.
- [ ] Merge the branch to `main` before marking Phase 1 `[completed]` in the roadmap.

## Acceptance Criteria

- A tracked text hunk can be captured into a named versioned profile without changing the worktree or index.
- Save and Pause removes exactly the captured content and preserves unrelated changes.
- Apply restores exactly the stored content and Pause reverses it again.
- Definitions persist under the Git common directory and are shared by linked worktrees.
- Applied state is derived independently for each working copy.
- Unsupported and corrupt data cannot be overwritten silently.
- Every unsupported MVP file state returns a specific error.
- No view, Sidebar type, File Status menu, stage behavior, commit behavior, Firebase schema, or cloud store changes in this phase.

## Explicit Non-Goals

- No UI or feature toggle.
- No profile Update workflow beyond initial capture.
- No stage or commit protection.
- No automatic behavior during checkout.
- No export/import or cloud sync.
- No untracked, binary, rename, deletion, conflict, or submodule support.

