# Inline Create Pull Request Phase 3

**Roadmap:** [`2026-08-15-inline-create-pull-request-roadmap.md`](2026-08-15-inline-create-pull-request-roadmap.md)

**Status:** [completed]

## Scope

1. Route Pull Requests header and inline submit actions through `MainWindowView` coordination callbacks.
2. Before provider creation, inspect the selected local source branch upstream state.
3. Publish a source branch without an upstream, push commits when it is ahead, and preserve the existing behind-branch safety check.
4. Reload provider context using the remote actually selected for publish before creating the Pull Request.
5. Keep the draft open and surface the concrete Git/push error if preparation fails.

## Acceptance Criteria

- A committed local source branch with no remote branch is automatically pushed and assigned an upstream before provider creation.
- Changing Source in the inline editor cannot bypass publish-before-create.
- Existing upstream branches push outstanding commits before creation.
- A behind branch or failed push never calls the provider create endpoint and leaves the draft available for recovery.
- The Pull Requests header, Workspace context menu, and branch context menu share the coordinated path.

## Verification

- `git diff --check` passed.
- `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build` passed.
- Targeted Pull Request tests compiled, but the XCTest host aborted before bootstrapping with the repository's known `Early unexpected exit` / `signal abrt` environment failure. The test command was not rerun.
