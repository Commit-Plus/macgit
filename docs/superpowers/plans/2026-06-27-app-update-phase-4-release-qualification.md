# Direct App Update Phase 4: Release Qualification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate the complete update path against a controlled test feed and document the operator checklist for production rollout.

**Architecture:** Keep Phase 4 focused on repeatable qualification, not runtime changes. Add a documented local test-feed setup, an end-to-end manual verification checklist, and production release notes that mirror the release workflow’s guarantees.

**Tech Stack:** Markdown docs, Sparkle appcast hosting, signed test builds, `xcodebuild`.

**Design spec:** [docs/superpowers/specs/2026-06-27-app-update-design.md](../specs/2026-06-27-app-update-design.md)

---

## File Structure

- Create `docs/release/app-update-e2e.md`: controlled-feed upgrade test.
- Create `docs/release/app-update-runbook.md`: production release checklist and rollback notes.

## Task 1: Document The Controlled Test-Feed Flow

**Files:**
- Create: `docs/release/app-update-e2e.md`

- [x] **Step 1: Add the end-to-end verification guide**

Create `docs/release/app-update-e2e.md`:

```markdown
# App Update E2E Verification

1. Install the previous signed and notarized Commit+ build into `/Applications/Commit+.app`.
2. Point that build at a controlled HTTPS test appcast URL.
3. Publish a newer signed build ZIP plus matching appcast entry to the test feed.
4. Launch the old build and verify no prompt appears automatically.
5. Confirm the repository sidebar shows `Update`.
6. Click `Update` and verify Sparkle's standard release notes window opens.
7. Start the download and verify the sidebar button changes to `Downloading…`.
8. Let Sparkle install and relaunch the app.
9. Verify the relaunched build reports the expected version and the sidebar banner is gone.
```

- [x] **Step 2: Commit the E2E guide**

Run:

```bash
git add docs/release/app-update-e2e.md
git commit -m "docs: add app update e2e verification"
```

Expected: a clean docs commit on `codex/app-update-phase-4-release-qualification`.

## Task 2: Document The Production Runbook

**Files:**
- Create: `docs/release/app-update-runbook.md`

- [x] **Step 3: Add the production rollout checklist**

Create `docs/release/app-update-runbook.md`:

```markdown
# App Update Release Runbook

1. Confirm `MARKETING_VERSION` matches the release tag without the `v` prefix.
2. Confirm `CURRENT_PROJECT_VERSION` increased since the previous public release.
3. Push the stable tag and wait for `Release App Update` to finish.
4. Verify the GitHub Release contains the signed Apple Silicon ZIP.
5. Verify the notarized app passes Gatekeeper locally.
6. Verify the public appcast changed only after the release asset became reachable.
7. Run the controlled test-feed checklist before changing the production feed.
8. If any release verification fails after publication, remove the appcast entry first so clients stop seeing the bad release.
```

- [x] **Step 4: Commit the runbook**

Run:

```bash
git add docs/release/app-update-runbook.md docs/superpowers/plans/2026-06-27-app-update-roadmap.md
git commit -m "docs: add app update release runbook"
```

Expected: a clean docs commit on `codex/app-update-phase-4-release-qualification`.
