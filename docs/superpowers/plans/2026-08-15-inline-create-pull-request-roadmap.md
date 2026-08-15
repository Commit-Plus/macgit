# Inline Create Pull Request Roadmap

**Goal:** Replace the constrained Create Pull Request sheet with an inline Pull Requests workspace that combines draft metadata, a local branch-comparison diff, and supported reviewer/assignee selection.

## Phases

| Phase | Scope | Status | Plan |
| --- | --- | --- | --- |
| 1 | Inline workspace navigation, draft form, full local changes, and diff rendering | [completed] | [`2026-08-15-inline-create-pull-request-phase-1.md`](2026-08-15-inline-create-pull-request-phase-1.md) |
| 2 | Provider-aware reviewer and assignee loading/submission with partial-failure handling | [completed] | [`2026-08-15-inline-create-pull-request-phase-2.md`](2026-08-15-inline-create-pull-request-phase-2.md) |
| 3 | Publish the selected local source branch before provider creation | [completed] | [`2026-08-15-inline-create-pull-request-phase-3.md`](2026-08-15-inline-create-pull-request-phase-3.md) |
| 4 | GitHub-inspired Pull Request detail hierarchy and Overview layout | [completed] | [`2026-08-15-inline-create-pull-request-phase-4.md`](2026-08-15-inline-create-pull-request-phase-4.md) |
| 5 | Provider-backed Pull Request merge action and list-cache tuning | [completed] | [`2026-08-15-inline-create-pull-request-phase-5.md`](2026-08-15-inline-create-pull-request-phase-5.md) |

## Shared Constraints

- `MainWindowView` coordinates authorization, publish-before-create, sidebar selection, and presentation state; feature views remain rendering/callback focused.
- Reuse `CommitFileListView` and `DiffView` for a read-only local `target...source` comparison.
- Preserve the current fail-closed changed-file validation and remote selection behavior.
- GitHub participant assignment may require follow-up requests after PR creation; a created PR must remain a success even if participant assignment partially fails.
- GitLab can include reviewer and assignee IDs in the create request.
- Unsupported providers or insufficient account permissions must omit or clearly disable participant controls.
- Do not launch the app. Targeted tests and a successful macOS build are the verification boundary.

## Completion

The roadmap is complete when every Create Pull Request entry point opens the inline workspace in the Pull Requests tab, draft branch changes render locally, cancellation and successful creation return to the list, supported providers can select and submit reviewers/assignees, targeted tests pass where the XCTest host permits, and the macOS build succeeds.
