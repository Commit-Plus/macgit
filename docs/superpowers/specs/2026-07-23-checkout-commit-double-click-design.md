# Checkout Commit by Double-Click

## Goal

Double-clicking a history commit should provide SourceTree-like checkout behavior. A commit on another branch should offer the existing branch checkout flow; a commit without a suitable branch ref should offer detached-HEAD checkout confirmation.

## UX

- Double-click any `CommitRowView`.
- If the commit has a local or remote branch ref, present the existing branch checkout sheet for that branch.
- Otherwise present the existing “Confirm change working copy” sheet.
- The detached-HEAD sheet displays “Discard local changes” only when the working copy has uncommitted changes. The option is unchecked by default.
- Cancel leaves the repository unchanged. OK runs the selected checkout operation through the existing repository-operation runner, refreshes repository state, and reports failures through the existing error alert.

## Architecture

`CommitRowView` exposes a double-click callback. `HistoryView` owns selection and presentation state, resolves branch refs from the commit’s refs, checks uncommitted-change count for detached checkout, and routes the operation to existing Git services and sheets. No Git subprocess is added to the row view.

## Safety and state

Checkout uses the existing non-forced Git checkout by default. Force checkout is used only when the user explicitly selects “Discard local changes”. Successful checkout posts `.repositoryDidChange` with the repository URL. Existing context-menu actions remain available.

## Verification

Build the macOS app with the repository’s prescribed `xcodebuild build` command. Add or update focused tests only where the branch-ref selection logic is extracted into a testable policy; do not launch the app.
