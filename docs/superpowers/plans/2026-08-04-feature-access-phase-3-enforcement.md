# Feature Access Phase 3: Repository and Pull Request Enforcement

**Branch:** `codex/feature-access-phase-3`

## Goal

Enforce the Firebase-backed plan policy at repository-opening and Pull Request entry points without allowing UI, menu, keyboard, or coordinator paths to bypass the same decision boundary.

## Current product surface

Commit+ currently has repository-opening and Pull Request surfaces, but it does not yet expose a Git Flow screen, command, or service. This phase keeps `.gitFlow` in the shared resolver and verifies its release matrix, but does not invent a new Git Flow product workflow. A future Git Flow entry point must call the same repository-scoped authorization helper before presenting UI or executing Git commands.

## Tasks

- [completed] Gate repository opening from the picker, clone completion, Open Recent, new windows, worktrees, and submodules before assigning the repository to a window.
- [completed] Gate Pull Request list presentation and every existing create/open Pull Request coordinator action.
- [completed] Add a shared denial presentation that distinguishes Pro upgrades, disabled features, unsupported repository scope, and unavailable visibility.
- [completed] Keep public and local-only Free behavior usable according to the release policy; fail closed for private or unknown visibility.
- [completed] Add focused policy/enforcement tests and verify the macOS build without launching the app.
- [completed] Mark Phase 3 complete in this plan and the roadmap after verification.

## Verification

- `FeatureAccessPolicyTests`, `FeatureAccessNoticeTests`, and `RepositoryVisibilityControllerTests` passed.
- `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build` passed.
- `git diff --check` passed.
- The app was not launched.

## Acceptance criteria

- Free can open local-only and hosted public repositories, but cannot open a confirmed private repository.
- Active Pro can open public, private, and local-only repositories; unknown visibility remains blocked for every plan.
- All repository-opening paths resolve access before mutating the window's active repository URL.
- Free can use Pull Requests on public repositories; private Pull Requests require active Pro.
- Pull Request list content is not instantiated while access is unresolved or denied.
- Branch and remote-branch Pull Request actions authorize before pushing, loading provider data, or opening a provider URL.
- A globally disabled feature is unavailable to Free and Pro.
- Denial UI offers Sign In for guests or Manage Account for signed-in Free users when Pro is required, and a retry path when visibility cannot be resolved.
- Policy changes and entitlement changes re-evaluate the visible Pull Request surface.
- There is no client-side quota ledger and no local repository path is written to Firebase or the feature-policy cache.
