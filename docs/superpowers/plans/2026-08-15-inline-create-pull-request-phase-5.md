# Pull Request Merge Phase 5

**Roadmap:** [`2026-08-15-inline-create-pull-request-roadmap.md`](2026-08-15-inline-create-pull-request-roadmap.md)

**Status:** [completed]

## Scope

1. Increase the session-scoped Pull Request list cache TTL to 120 seconds.
2. Remove browser-only Open Changes actions now that changes render inline.
3. Add a confirmed, provider-backed merge action to the Pull Request detail footer.
4. Support merge requests through GitHub and GitLab APIs.
5. Invalidate and refresh list, detail, and changes caches after a successful merge.

## Acceptance Criteria

- Repeated list loads within two minutes use the controller cache unless explicitly refreshed.
- The detail footer shows a green Merge Pull Request button and no Open Changes button.
- Closed, draft, merged, or provider-blocked pull requests cannot invoke merge.
- Merge requires confirmation before updating the remote repository.
- Successful merges refresh provider state; failures surface their provider message.
- Provider and controller merge behavior has targeted test coverage.

## Verification

- `git diff --check` passed.
- The macOS `xcodebuild` build passed.
- Targeted merge tests compiled, but the XCTest host aborted before bootstrapping; they were not rerun per repository instructions.
- Runtime app launch and visual inspection were not performed per repository instructions.
