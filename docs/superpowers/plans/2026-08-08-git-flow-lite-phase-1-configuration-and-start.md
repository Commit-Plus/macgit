# Git Flow Lite Phase 1: Configuration and Start Flows

**Branch:** `codex/git-flow-lite-phase-1`

## Tasks

- [completed] Add Codable Git Flow configuration, topic-kind, role-detection, validation, and Start-plan models.
- [completed] Persist configuration locally against the Git common directory with backward-safe defaults.
- [completed] Add Git service operations for configuration discovery and safe topic-branch creation.
- [completed] Add a compact Git Flow setup surface to Repository Settings.
- [completed] Add Start Feature, Bugfix, Release, and Hotfix actions and sheets to the main-window workflow menu.
- [completed] Refresh repository state and register branch-creation Undo only after Start succeeds.
- [completed] Add focused model/store/integration tests, run `git diff --check`, and build the macOS app without launching it.

## Acceptance criteria

- A repository can enable Git Flow by selecting existing Main and Develop branches.
- Default prefixes are `feature/`, `bugfix/`, `release/`, and `hotfix/` and each can be edited to another valid non-empty prefix.
- Feature and Bugfix start at Develop; Release starts at Develop; Hotfix starts at Main.
- Start shows the resolved full branch name and base branch before execution.
- Start is blocked for a dirty working tree, missing base branch, invalid or existing branch name, an in-progress Git operation, or an incompatible linked-worktree checkout.
- A successful Start creates and checks out exactly one local branch, refreshes repository state, and exposes a safe Undo entry.
- Configuration never creates a tracked repository file and never syncs through Firebase.
- Existing branch, settings, toolbar, and repository-operation behavior remains unchanged when Git Flow is disabled.

## Explicit non-goals

- No Finish action in Phase 1.
- No tag creation.
- No push or remote mutation.
- No new-worktree creation.
- No branch-role badge polish.

## Result

- Git Flow configuration is stored under the Git common directory and is shared by linked worktrees without touching tracked files.
- Repository Settings exposes Main, Develop, and the four editable prefixes; Git Flow actions open the correct settings tab directly.
- Start Feature, Bugfix, Release, and Hotfix create and check out branches from their configured base after safety validation.
- Start registers a compound Undo that checks out the previous ref and deletes the created branch only while its expected tip still matches.
- Nine focused tests pass, `git diff --check` passes, and the macOS app builds successfully without being launched.
