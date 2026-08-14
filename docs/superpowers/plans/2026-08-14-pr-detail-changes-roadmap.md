# Pull Request Detail Changes Roadmap

**Goal:** Add an in-app Changes tab to Pull Request detail while preserving the existing Overview experience for description, assignees, comments, and comment composition.

## Phases

| Phase | Scope | Status | Plan |
| --- | --- | --- | --- |
| 1 | Provider change APIs, controller cache, Overview/Changes UI, read-only diff rendering, and tests | [completed] | [`2026-08-14-pr-detail-changes-phase-1.md`](2026-08-14-pr-detail-changes-phase-1.md) |

## Shared Constraints

- Pull Request changes are fetched through the provider API so fork-based PRs and unfetched remote refs work.
- The existing Overview content and comment workflow remain unchanged.
- Changes load lazily and use a session-only controller cache.
- Reuse the app's existing file list and diff presentation in read-only mode; do not expose stage, discard, or patch mutation actions.
- Provider omissions, binary files, collapsed files, and oversized diffs show an explicit unavailable state with a browser fallback.
- GitHub and GitLab share provider-neutral models and controller behavior.
- Do not launch the app. Focused tests and a successful macOS build are the automated verification boundary.

## Completion

The roadmap is complete when both supported providers can load paginated changed-file data, the PR detail can switch between Overview and Changes, supported patches render with the existing diff UI, unavailable patches retain an Open Changes fallback, targeted tests pass, and the macOS build succeeds.
