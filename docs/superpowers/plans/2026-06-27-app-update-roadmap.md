# Direct App Update Roadmap

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a secure GitHub Releases based update system for Commit+ that checks once per launch, shows an `Update` button in the sidebar when a newer stable build exists, and lets Sparkle handle download, install, and relaunch.

**Architecture:** The feature is split into four independently verifiable phases. Phase 1 adds Sparkle, generated Info.plist settings, and an app-wide `AppUpdateController` behind a testable adapter. Phase 2 adds the sidebar banner and window wiring. Phase 3 adds signing, notarization, packaging, appcast generation, and release publication. Phase 4 adds end-to-end release qualification and operator documentation.

**Tech Stack:** Swift 6, SwiftUI, Sparkle 2, XCTest, Xcode build settings, GitHub Actions, Developer ID signing, Apple notarization, GitHub Releases, GitHub Pages.

**Design spec:** [docs/superpowers/specs/2026-06-27-app-update-design.md](../specs/2026-06-27-app-update-design.md)

---

## Plan Index

- Phase 1: [completed] [2026-06-27-app-update-phase-1-sparkle-foundation.md](2026-06-27-app-update-phase-1-sparkle-foundation.md) (branch: `codex/app-update-phase-1-sparkle-foundation`, commit: `8c7f3a5`)
- Phase 2: [completed] [2026-06-27-app-update-phase-2-sidebar-experience.md](2026-06-27-app-update-phase-2-sidebar-experience.md) (branch: `codex/app-update-phase-2-sidebar-experience`, commit: `3127eed`)
- Phase 3: [completed] [2026-06-27-app-update-phase-3-release-automation.md](2026-06-27-app-update-phase-3-release-automation.md) (branch: `codex/app-update-phase-3-release-automation`)
- Phase 4: [pending] [2026-06-27-app-update-phase-4-release-qualification.md](2026-06-27-app-update-phase-4-release-qualification.md)

## Recommended Order

1. Finish Phase 1 first. It creates the updater integration, app lifecycle ownership, background check policy, and tests that every later UI step depends on.
2. Do Phase 2 next. It only needs the controller surface from Phase 1 and can stay focused on the requested sidebar behavior.
3. Do Phase 3 after the in-app flow is stable. Release automation should package the exact updater-enabled app that local tests already verified.
4. Do Phase 4 last. It validates the full signed-release path against a controlled feed and produces the release checklist used before production rollout.

## Shared Rules For Every Phase

- Never implement app-update phase code directly on `main`; use an isolated `codex/app-update-phase-*` branch/worktree.
- Keep Sparkle-specific API details behind small local wrappers so tests can use fakes without network access or updater windows.
- Sidebar-only state is limited to `idle`, `checking`, `available`, and `downloading`; detailed release notes and install flow remain in Sparkle UI.
- Silent launch checks never surface repository-style errors. Manual menu checks may use Sparkle's user-facing UI.
- Every non-trivial phase ends with `xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test`.
- Mark a phase `[completed]` here only after the feature branch has fresh green verification for that phase's scoped tests and the full test suite.

## Phase Boundaries

- Phase 1 owns package integration, app config keys, `AppUpdateController`, updater protocol/fake, launch-time background check, and the app-menu `Check for Updates...` action.
- Phase 2 owns `UpdateBannerView`, sidebar placement, state-to-label rendering, and shared controller injection across repository windows.
- Phase 3 owns Sparkle feed metadata, GitHub Actions, signing/notarization verification scripts, and publication ordering.
- Phase 4 owns controlled-feed upgrade validation, release runbook, and the production enablement checklist.

## Self-Review

Spec coverage:

- Launch-time silent check: Phase 1.
- Shared app-wide controller and manual menu action: Phase 1.
- Sidebar `Update` / `Downloading…` behavior: Phase 2.
- GitHub Releases + GitHub Pages publishing: Phase 3.
- Controlled feed and operator verification: Phase 4.

Placeholder scan:

- Every phase listed above has a concrete plan file and a fixed branch naming pattern.

Type consistency:

- The roadmap assumes the same cross-phase types from the design spec: `AppUpdateController`, `AppUpdateState`, `AppUpdaterProtocol`, and `UpdateBannerView`.
