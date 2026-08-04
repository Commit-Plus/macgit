# Feature Access Phase 3: Repository Action Enforcement

**Branch:** `codex/feature-access-phase-3`

## Goal

Allow every plan to open and clone repositories, then enforce the Firebase-backed plan policy at paid action entry points without allowing UI, menu, keyboard, or coordinator paths to bypass the same decision boundary.

## Current product surface

Commit+ currently exposes Pull Request and Git Undo actions, but it does not yet expose a Git Flow screen, command, or service. Pull Requests and Git Undo use the shared repository-scoped authorization boundary. A future Git Flow entry point must call the same helper before presenting UI or executing Git commands.

## Tasks

- [completed] Keep repository opening, clone completion, Open Recent, new windows, worktrees, and submodules available to every plan.
- [completed] Gate Pull Request list presentation and every existing create/open Pull Request coordinator action.
- [completed] Gate Git Undo and Redo from the shared toolbar, menu, and keyboard action coordinator.
- [completed] Add a reusable Pro upgrade sheet plus denial presentation for disabled features, unsupported repository scope, and unavailable visibility.
- [completed] Keep public and local-only Free actions usable according to the release policy; fail closed for private or unknown visibility at gated actions.
- [completed] Add focused policy/enforcement tests and verify the macOS build without launching the app.
- [completed] Mark Phase 3 complete in this plan and the roadmap after verification.

## Verification

- The earlier Pull Request and repository-visibility policy tests passed before the product boundary changed.
- Git Undo policy coverage was added but not rerun under the macOS build-only verification instruction.
- `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build` passed after the Git Undo gate and reusable upgrade sheet were added.
- `git diff --check` passed.
- The app was not launched.

## Acceptance criteria

- Free and Pro can open and clone public, private, and local-only repositories without an entitlement check.
- Free can use Pull Requests on public repositories; private Pull Requests require active Pro.
- Free can use Git Undo and Redo on public and local-only repositories; private Git Undo and Redo require active Pro and present the reusable upgrade sheet.
- Pull Request list content is not instantiated while access is unresolved or denied.
- Branch and remote-branch Pull Request actions authorize before pushing, loading provider data, or opening a provider URL.
- Toolbar, menu, and keyboard Git Undo entry points authorize before removing an entry from the undo or redo stack.
- A globally disabled feature is unavailable to Free and Pro.
- Denial UI offers Sign In for guests or View Pricing for signed-in Free users when Pro is required, and a retry path when visibility cannot be resolved.
- Policy changes and entitlement changes re-evaluate the visible Pull Request surface.
- There is no client-side quota ledger and no local repository path is written to Firebase or the feature-policy cache.
