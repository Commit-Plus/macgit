# Git Flow Lite Phase 2: Feature and Bugfix Finish

Status: completed on `codex/git-flow-lite-phase-2`.

## Goal

Make Feature and Bugfix usable end to end, and expose Git Flow as a first-class sidebar workflow instead of only a toolbar command.

## Scope

- Add an expandable `GIT FLOW` sidebar section when Git Flow is enabled.
- Show Start Feature, Bugfix, Release, and Hotfix actions in the expanded section.
- Add a Tower-style native context menu with Start/Finish pairs, Edit Workflow, and Disable Workflow.
- Enable Finish only for the matching current topic branch; Release and Hotfix Finish remain disabled until Phase 3.
- Finish Feature/Bugfix by checking out Develop, merging with `--no-ff`, and optionally deleting the local topic branch.
- Register guarded compound Undo/Redo after a successful finish.
- Preserve the source branch and surface Git's conflict state when a merge conflicts.

## Verification

- Focused planner, service, policy, sidebar state, and Undo tests.
- `git diff --check`.
- macOS build. Do not launch the app.
