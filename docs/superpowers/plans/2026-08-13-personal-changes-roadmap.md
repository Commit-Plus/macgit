# Personal Changes Roadmap

**Design:** [`docs/superpowers/specs/2026-08-13-personal-changes-design.md`](../specs/2026-08-13-personal-changes-design.md)

**Goal:** Let users keep named, long-lived personal patches in tracked working files, apply or pause them safely, and prevent Commit+ from staging them by default while leaving Git's real working-tree state visible.

## Phases

| Phase | Scope | Status | Plan |
| --- | --- | --- | --- |
| 1 | Domain model, Git-common-directory store, patch capture/inspection, Apply/Pause engine | [pending] | [`2026-08-13-personal-changes-phase-1-foundation.md`](2026-08-13-personal-changes-phase-1-foundation.md) |
| 2 | Sidebar section, profile detail, File Status menus, hunk/line capture, state badges | [pending] | [`2026-08-13-personal-changes-phase-2-ui-and-capture.md`](2026-08-13-personal-changes-phase-2-ui-and-capture.md) |
| 3 | Protected whole-file and partial staging, external-stage detection, commit guard | [pending] | [`2026-08-13-personal-changes-phase-3-protected-staging.md`](2026-08-13-personal-changes-phase-3-protected-staging.md) |
| 4 | Update/remove/delete semantics, branch/worktree lifecycle, drift recovery, hardening | [pending] | [`2026-08-13-personal-changes-phase-4-lifecycle-and-recovery.md`](2026-08-13-personal-changes-phase-4-lifecycle-and-recovery.md) |
| 5 | Portable export/import package for deliberate transfer between Macs | [pending] | [`2026-08-13-personal-changes-phase-5-portability.md`](2026-08-13-personal-changes-phase-5-portability.md) |

## Phase Dependencies

```text
Phase 1: trusted local patch engine
    ↓
Phase 2: user-facing capture and management
    ↓
Phase 3: stage and commit protection
    ↓
Phase 4: lifecycle and recovery hardening
    ↓
Phase 5: explicit cross-machine portability
```

- Phase 2 must not reproduce patch state logic in SwiftUI; it consumes Phase 1 controller/service results.
- Phase 3 starts only after capture and Apply/Pause semantics are stable enough to identify personal content deterministically.
- Phase 4 treats all earlier entry points as one lifecycle and must close bypasses before adding branch-aware convenience.
- Phase 5 exports the stable schema from Phase 4. It must not freeze a provisional Phase 1 schema into a public file format.

## Shared Constraints

- Git continues to track every managed file and report applied content as modified.
- Personal ownership is hunk/line-based. A managed file may contain ordinary changes that remain stageable.
- Add defaults to Keep Applied and does not mutate the working file.
- Protection defaults on and covers every Commit+-initiated stage/commit path.
- Other Git clients and the CLI remain capable of staging personal content; Commit+ detects and reports that state without silently undoing it.
- Apply/Pause/Revert preflight the complete operation and never fall back to reset, checkout, or file overwrite.
- Definitions live under `<git-common-dir>/commitplus/personal-changes/`; no tracked file, stash, hidden commit, `skip-worktree`, or `assume-unchanged` flag is used.
- Views remain rendering/callback surfaces. `MainWindowView` coordinates, dedicated Personal Changes services plan/inspect, and `GitStatusService` executes Git.
- Local paths, file contents, patches, credentials, branch state, and worktree state do not sync to Firebase in this roadmap.
- Every new Swift file begins with the AGPL v3 header.
- Do not launch the app. Focused tests and a successful macOS build are the automated verification boundary; record manual UI acceptance as unverified when it is not exercised.

## Branch Kickoff for Every Phase

Each phase is independent work and starts only after the previous phase is merged:

```bash
rtk git switch main
rtk git status --short --branch
rtk git pull --ff-only
rtk git switch -c codex/personal-changes-phase-<n>-<slug>
```

The working tree must be clean and `main` must contain the preceding completed phase. If either condition is false, stop and ask the user rather than stashing or moving their changes.

Recommended branches:

- `codex/personal-changes-phase-1-foundation`
- `codex/personal-changes-phase-2-ui-and-capture`
- `codex/personal-changes-phase-3-protected-staging`
- `codex/personal-changes-phase-4-lifecycle-recovery`
- `codex/personal-changes-phase-5-portability`

## MVP Boundary

Phase 3 is the first product-complete MVP: a user can create/manage profiles and Commit+ protects them from accidental staging and commit.

Phase 4 is the reliability release required before enabling the feature broadly. Phase 5 adds deliberate cross-machine transport without introducing a cloud security boundary.

## Follow-Up Roadmap Gate

Automatic cloud sync is intentionally not a Phase 6 here. Start a separate roadmap only after all of these decisions are approved:

- End-to-end encryption and key transfer/recovery model.
- Object-storage choice, quota, retention, deletion, and offline behavior.
- Canonical repository identity and remote-less repository behavior.
- Concurrent device edits, tombstones, version history, and conflict UX.
- Explicit metadata that may be visible to Firebase versus encrypted payload fields.

The portable package from Phase 5 is the only supported cross-machine transfer until that follow-up lands.

## Completion

The roadmap is complete when all five phases are merged to `main`; tracked text hunks can be captured, inspected, applied, paused, updated, removed, and safely deleted; every Commit+ stage/commit path respects protection; external staging and branch/worktree drift are recoverable; portable packages round-trip without local paths or credentials; focused tests and final macOS build pass; and all phase rows are marked `[completed]` only after merge.

