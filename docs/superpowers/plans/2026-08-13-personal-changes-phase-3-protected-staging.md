# Personal Changes Phase 3: Protected Staging and Commit Guard

**Branch:** `codex/personal-changes-phase-3-protected-staging`

**Goal:** Make `Protect from staging in Commit+` true across every Commit+ stage and commit path while continuing to stage ordinary changes from files that also contain personal hunks.

**Architecture:** `PersonalChangeStagePlanner` creates a candidate index through a temporary alternate Git index and produces a real-index patch without touching working files. `GitStatusService` owns alternate-index execution and performs an expected-index guard before mutation. Pure patch classification handles hunk/line requests. A centralized commit guard inspects protected profiles before every Git commit entry point.

## Prerequisites

- Phases 1 and 2 are merged to `main`.
- Capture, inspection, and profile classification tests pass on the clean Phase 3 base.
- Audit all current stage/commit callers, including `FileStatusView`, `DiffView`, `SyncState.performCommit(commitAllChanges:)`, quick actions, double-click, drag/drop paths, Undo/Redo, and conflict completion.
- Record the real-index behavior for existing staged content and renames before changing stage services.

## Tasks

### Task 1: Add alternate-index execution and expected-index guards

**Files:**

- Modify: `macgit/Services/GitCommandRunning.swift`
- Create: `macgit/Services/GitIndexSnapshot.swift`
- Create: `macgit/Services/PersonalChangeAlternateIndex.swift`
- Modify: `macgit/Services/GitStatusService+PersonalChanges.swift`
- Test: `macgitTests/PersonalChangeAlternateIndexTests.swift`

- [ ] Support an explicit `GIT_INDEX_FILE` override without mutating the global process environment.
- [ ] Snapshot the current index tree and a stable index identity before planning.
- [ ] Create temporary indexes in a unique temporary directory, copy/initialize from the real index safely, and clean all temporary files on every exit path.
- [ ] Refuse the final mutation if the real index identity changed after planning.
- [ ] Never delete `.git/index.lock`, replace the real index blindly, or run checkout/reset as a fallback.
- [ ] Test repositories with no index file yet, existing staged content, split ordinary changes, executable mode, concurrent index mutation, Git failure, and cleanup failure reporting.

### Task 2: Implement protected whole-file and multi-file staging

**Files:**

- Create: `macgit/Services/PersonalChangeStagePlanner.swift`
- Create: `macgit/Services/GitStatusService+PersonalChangeStage.swift`
- Modify: `macgit/Services/GitStatusService+Stage.swift`
- Test: `macgitTests/PersonalChangeProtectedStageIntegrationTests.swift`

- [ ] Load active protected profiles and classify requested paths before using plain `git add`.
- [ ] For unmanaged paths, retain the existing fast path and rename behavior.
- [ ] For managed paths, base an alternate index on the real index, stage requested working files there, reverse only applicable protected personal patches there, then diff candidate tree against the original real-index tree.
- [ ] Apply the candidate diff to the real index only after the expected-index check passes.
- [ ] Preserve unrelated pre-existing staged changes and leave working files byte-identical.
- [ ] Reject mixed/conflicted/partially-applied profile state with a specific recovery action instead of staging the whole path.
- [ ] Make Stage, Stage Selected, Stage All, quick action, and double-click route through the same protected service.
- [ ] Cover a file containing personal hunk A plus ordinary hunk B: B is staged, A remains unstaged and applied.
- [ ] Cover multiple profiles/files, all-personal paths yielding no index change, disabled protection yielding normal staging, and index races.

### Task 3: Protect hunk and line staging

**Files:**

- Create: `macgit/Services/PersonalChangePatchClassification.swift`
- Modify: `macgit/Views/Common/DiffView.swift`
- Modify: `macgit/Views/FileStatus/FileStatusView.swift`
- Modify: `macgit/Services/GitStatusService+Stage.swift`
- Test: `macgitTests/PersonalChangePatchClassificationTests.swift`
- Test: `macgitTests/PersonalChangePartialStageIntegrationTests.swift`

- [ ] Classify each requested patch as ordinary, protected personal, or mixed using stored patch content/fingerprints and current inspection evidence.
- [ ] Ordinary hunk/line requests continue through the existing cached patch route.
- [ ] Protected personal requests are blocked with the profile name and Review/Remove from Profile choices.
- [ ] Mixed requests require narrowing the selected lines or an explicit Stage Anyway confirmation; never subtract ambiguous overlapping lines automatically.
- [ ] Stage Anyway is request-scoped, does not switch off profile protection globally, and records no hidden state.
- [ ] Ensure right-click, hunk buttons, selected-line menus, keyboard/quick actions, and any future callback path use the same classification policy.

### Task 4: Detect external staging and centralize the commit guard

**Files:**

- Create: `macgit/Services/PersonalChangeCommitGuard.swift`
- Modify: `macgit/Services/GitStatusService+Commit.swift`
- Modify: `macgit/Services/SyncState.swift`
- Modify: `macgit/Views/FileStatus/FileStatusView.swift`
- Modify as required: `macgit/Views/Common/ConflictMergeToolView.swift`
- Create: `macgit/Views/PersonalChanges/PersonalChangeStagedWarningSheet.swift`
- Test: `macgitTests/PersonalChangeCommitGuardTests.swift`
- Test: `macgitTests/PersonalChangeExternalStageIntegrationTests.swift`

- [ ] Inspect protected patches against the real index during normal refresh and immediately before commit.
- [ ] Distinguish fully staged, partially staged, and not staged personal content.
- [ ] Block commit by default whenever protected content is staged, regardless of whether staging occurred inside Commit+ or externally.
- [ ] Offer Review Staged Diff, Unstage Personal Changes, and an explicit Keep Staged/Commit Anyway path.
- [ ] Unstage Personal Changes reverses only verified protected content from the index and leaves the working tree untouched.
- [ ] Add an explicit service-level commit override parameter so every direct `GitStatusService.commit` caller is guarded by default, including `SyncState` commit-all and conflict completion.
- [ ] Preserve Undo/Redo expected-ref semantics; do not let a redo bypass protection accidentally.
- [ ] Protect `stageAllChanges(in:)` centrally so a non-File-Status caller cannot bypass the alternate-index path.

### Task 5: Release the MVP and verify every entry point

- [ ] Add an entry-point matrix test or documented test table covering:
  - File quick Stage.
  - File double-click.
  - Ellipsis and context-menu Stage.
  - Stage Selected and Stage All.
  - Diff hunk and selected-line Stage.
  - Commit with pre-staged changes.
  - Commit All through `SyncState`.
  - External `git add` followed by Commit+ commit.
  - Explicit Stage Anyway and Commit Anyway.
- [ ] Run all Personal Changes tests, relevant existing stage/undo tests, `rtk git diff --check`, and the macOS build sequentially.
- [ ] Do not launch the app; record confirmation-dialog attachment, badge state, and staged-warning interaction as manual runtime acceptance.
- [ ] Remove the Phase 2 incomplete-protection warning only after every entry point is covered.
- [ ] Merge to `main` before marking Phase 3 `[completed]`.

## Acceptance Criteria

- A protected applied personal hunk remains unstaged after every default Commit+ whole-file or multi-file stage action.
- Ordinary hunks in the same file stage and commit normally.
- Protected hunk/line staging is blocked unless the user explicitly overrides it.
- External staging is detected; Commit+ does not silently unstage it, but blocks commit until the user chooses a recovery or override.
- Existing staged changes survive alternate-index planning.
- Working files remain byte-identical during protected staging and unstaging.
- Index races fail before mutation with an actionable error.
- Repositories without protected profiles preserve current stage and commit behavior.

## Explicit Non-Goals

- No prevention of commits made entirely outside Commit+.
- No Git hooks installed into user repositories.
- No automatic profile removal after Commit Anyway.
- No ambiguous mixed-line subtraction.
- No branch auto-apply, export/import, or cloud sync.

