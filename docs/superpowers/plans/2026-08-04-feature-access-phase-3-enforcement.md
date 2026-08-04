# Feature Access Phase 3: Repository Action Enforcement

**Branch:** `codex/feature-access-phase-3`

## Goal

Allow every plan to open and clone repositories, then enforce the Firebase-backed plan policy at paid action entry points without allowing UI, menu, keyboard, or coordinator paths to bypass the same decision boundary.

## Current product surface

Commit+ keeps core Git operations, Git Undo, and manual conflict resolution available on every repository. Pull Request collaboration uses the shared repository-scoped authorization boundary. The app does not yet expose a Git Flow screen, command, or service; a future Git Flow entry point must call the same helper before presenting UI or executing Git commands.

## Tasks

- [completed] Keep repository opening, clone completion, Open Recent, new windows, worktrees, and submodules available to every plan.
- [completed] Gate Pull Request list presentation and every existing create/open Pull Request coordinator action.
- [completed] Keep Git Undo, Redo, and both File Status “Resolve Manually…” entry points available as core Git safety tools.
- [completed] Add a reusable Pro upgrade sheet for private Pull Requests plus denial presentation for disabled features, unsupported repository scope, and unavailable visibility.
- [completed] Keep public and local-only Free actions usable according to the release policy; fail closed for private or unknown visibility at gated actions.
- [completed] Add focused policy/enforcement tests and verify the macOS build without launching the app.
- [completed] Mark Phase 3 complete in this plan and the roadmap after verification.

## Verification

- The earlier Pull Request and repository-visibility policy tests passed before the product boundary changed.
- `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build` passed after the reusable upgrade sheet and final core-Git boundary were applied.
- `git diff --check` passed.
- The app was not launched.

## Acceptance criteria

- Free and Pro can open and clone public, private, and local-only repositories without an entitlement check.
- Free can use Pull Requests on public repositories; private Pull Requests require active Pro.
- Free and Pro can use Git Undo, Redo, and manual conflict resolution on every repository.
- Pull Request list content is not instantiated while access is unresolved or denied.
- Branch and remote-branch Pull Request actions authorize before pushing, loading provider data, or opening a provider URL.
- A globally disabled feature is unavailable to Free and Pro.
- Denial UI offers Sign In for guests or View Pricing for signed-in Free users when Pro is required, and a retry path when visibility cannot be resolved.
- Policy changes and entitlement changes re-evaluate the visible Pull Request surface.
- There is no client-side quota ledger and no local repository path is written to Firebase or the feature-policy cache.
