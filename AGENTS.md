# macgit AGENTS.md

## Project: macgit (Commit+)
A macOS Git client built with Swift and SwiftUI. Zero external dependencies; Git is driven via `Process()` subprocess. See `README.md` for build/run details and the full feature list.

## Build & Test

```bash
# Build
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build

# Run tests
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test
```

Always run the test command after non-trivial changes. Tests live in `macgitTests/` (XCTest, real temp Git repos for integration tests).

> **Agent note:** Do not launch the app after a successful build. Verification is complete once `xcodebuild` succeeds and the unit tests pass; the user will handle any manual UI testing.

## Architecture

```
macgit/
├── App/                 # App entry point, AppState, ToolbarAction, menu/toolbar wiring
├── Views/               # SwiftUI views (MainWindow, FileStatus, History, Search, Stashes, Common)
├── Services/            # Git operations & business logic (GitStatusService + extensions)
├── Models/              # Data models
├── ViewModels/          # View models
└── Resources/           # Assets
```

Git operations are centralized in `macgit/Services/GitStatusService*.swift` (split into `+Stage`, `+Commit`, `+Diff`, `+Branch`, `+Remote`, `+MergeStash`, `+Search`, `+Status` extensions).

---

## Workflow Conventions

### 1. Superpowers skills usage (use sparingly)

This repo has the **superpowers** plugin installed, but skills are expensive (high token cost) and often over-engineer simple problems.

- **For simple/similar issues or straightforward tasks** — do NOT use superpower skills. Just do the work directly.
- **For genuinely complex or multi-step tasks** — ask the user first before invoking any skill. Explain which skill you think applies and why (e.g. token cost, risk of over-engineering). Proceed only if the user approves.

### 2. OpenSpec is deprecated
**OpenSpec is outdated for this project and no longer used.** Do not create or follow OpenSpec specs. All design specs and implementation plans now live under `docs/superpowers/`:
- `docs/superpowers/specs/` — design specs (per-feature design docs)
- `docs/superpowers/plans/` — implementation plans and roadmaps (checkbox-driven, task-by-task)

### 3. Complex features require a Superpowers plan roadmap
For implementing a complex feature, first produce a **Superpowers plan as a roadmap** in `docs/superpowers/plans/`, following the pattern of the existing Git Undo roadmap:

- **Roadmap file** (e.g. `docs/superpowers/plans/2026-06-19-git-undo-roadmap.md`) — the top-level plan that links to one sub-plan per phase, lists the recommended implementation order, and tracks phase status.
- **Per-phase plan files** (e.g. `2026-06-19-git-undo-phase-0-1a.md`) — detailed, TDD-style, checkbox-driven task lists for a single phase that an agent can execute independently.

Each plan file should declare its REQUIRED SUB-SKILL (`superpowers:subagent-driven-development` or `superpowers:executing-plans`) at the top so executing agents know how to run it.

### 4. Mark phase status in the roadmap when a phase completes
**When an agent completes a phase, it must update that phase's status to completed in the roadmap file.** In the roadmap's "Plan Index", annotate each phase line with a status marker:

- `[pending]` — not started
- `[in progress]` — actively being worked on (include the branch/worktree name)
- `[completed]` — merged/finished (include the merge commit or branch it landed on)

Example:
```
- Phase 0 + 1A: [completed] 2026-06-19-git-undo-phase-0-1a.md (branch: codex/git-undo-phase-0-1a)
- Phase 1B:    [completed] 2026-06-19-git-undo-phase-1b-hunks-lines.md (branch: codex/git-undo-phase-1b)
- Phase 2:     [in progress] 2026-06-19-git-undo-phase-2-commits.md (worktree: codex-git-undo-phase-2)
- Phase 3A:    [pending] 2026-06-19-git-undo-phase-3a-stash-save-drop.md
```

Update the marker as soon as a phase's code is verified (tests green), not just when the plan is written.

### 5. Use git worktrees for isolated phase work
Phase implementations are developed in isolated worktrees under `.worktrees/` (see the `using-git-worktrees` skill). Never do phase work directly on `main`. The `main` branch currently holds only the roadmap + plan docs for in-flight features; the actual code lands on `codex/<phase>` branches and is merged when ready.

---

## Current Feature Status: Git Undo Roadmap

**Roadmap:** `docs/superpowers/plans/2026-06-19-git-undo-roadmap.md`

Tower-style Git Undo, implemented phase-by-phase. Shared types created in Phase 0+1A: `GitUndoOperation`, `GitUndoEntryFactory`, `GitUndoExecutor`, `GitUndoManager` (all in `macgit/Services/GitUndo*.swift`).

| Phase | Scope | Status |
|-------|-------|--------|
| 0 + 1A | Undo/redo infra + file-level stage/unstage | Merged to `main` |
| 1B | Hunk/line stage undo | Merged to `main` |
| 2 | Commit undo | Merged to `main` |
| 3A | Stash save/drop undo | Merged to `main` |
| 3B | Stash apply/pop undo | Merged to `main` |
| 4 | Local branch actions undo | Merged to `main` |
| 5 | Discard/remove undo (`.git/macgit/undo` backups) | Merged to `main` at `0115a7f` |
| 6 | History actions (cherry-pick/revert/reset/merge/rebase) | Merged to `main` at `177ffb9` |
| 7 | Remote actions (pull rollback, published branch removal) | Merged to `main` at `c896c28` |

**Shared rules for every phase** (from the roadmap): undo entries are registered only after the original Git action succeeds; every undo/redo refreshes `SyncState` and posts `.repositoryDidChange`; destructive inverses check an expected state before running; if a precondition fails the popped entry is restored and an error is shown; undo stacks are not persisted across app launches.

> Note: `main` now contains the merged Git Undo implementation through Phase 7. Active phase work should still happen on isolated `codex/<phase>` branches and merge back only after tests pass.

---

## Recent Changes

### Menu Bar Actions Enable/Disable Logic (2026-06-16)
**Problem:** The Actions menu in the menu bar was always disabled because the `@FocusedValue` / `@FocusedBinding` mechanism in macOS SwiftUI doesn't reliably work with `NavigationSplitView`. The focus values set by `MainWindowView` were never picked up by the `CommandMenu` in `macgitApp.swift`.

**Solution:**
1. **Actions are handled via Notifications** — `macgitApp.swift` posts `Notification.Name.toolbarAction` (defined in `ToolbarAction.swift`) when a menu button is clicked. `MainWindowView` listens for this notification and calls `handleToolbarAction(_:)`.
2. **Enable/disable is based on `AppState.hasOpenRepository`** — The `Actions` menu buttons are disabled when `appState.hasOpenRepository == false` (i.e., when the `RepoPickerView` is shown). When a repository is open, all buttons are enabled.
3. **The actual guard logic (syncing, staged count, etc.) lives in `handleToolbarAction`** — This is the same function used by toolbar buttons, so the behavior is consistent.

**Files involved:**
- `macgit/App/ToolbarAction.swift` — Defines `ToolbarAction` enum, `ToolbarActionState` struct, and `Notification.Name.toolbarAction`
- `macgit/App/macgitApp.swift` — `CommandMenu("Actions")` posts notifications and uses `.disabled(!appState.hasOpenRepository)`
- `macgit/Views/MainWindow/MainWindowView.swift` — Listens for `.toolbarAction` notification and calls `handleToolbarAction`

**Note:** The old `@FocusedValue` / `@FocusedBinding` / `focusedSceneValue` approach was abandoned because it doesn't work reliably in this SwiftUI + NavigationSplitView setup on macOS. The notification-based approach is robust and explicit. This same notification pattern is reused by the Git Undo menu actions (`macgit/App/GitUndoMenuAction.swift`).
