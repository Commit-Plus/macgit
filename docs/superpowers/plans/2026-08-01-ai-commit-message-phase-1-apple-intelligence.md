# AI Commit Message Phase 1: Apple Intelligence

**Branch:** `codex/apple-intelligence-commit-message`

## Tasks

- [completed] Add provider-neutral request, response, availability, registry, selection, and generation-controller seams.
- [completed] Build a bounded staged-diff context and fingerprint without mutating the Git index.
- [completed] Implement the Apple Intelligence provider with Foundation Models availability and context-error handling.
- [completed] Add the AI provider dropdown and Generate action to the expanded File Status commit bar.
- [completed] Add AI Providers settings with Apple Intelligence status and placeholder API-key controls for OpenAI, Claude, and Gemini.
- [completed] Add focused tests, run `git diff --check`, and build the macOS app without launching it.

## Acceptance criteria

- Apple Intelligence is selected by default and clearly labeled as on-device.
- OpenAI, Claude, and Gemini appear as disabled placeholders in the commit dropdown and Settings.
- Generate is disabled when there are no staged changes or the selected provider is unavailable.
- Generated output fills the existing editor and never triggers a commit.
- A stale response cannot overwrite the editor after staged changes or provider selection changes.
- Large staged diffs are bounded to the Apple model context and fail with a user-visible error when generation cannot continue.
- No API key or source diff is written to Firebase, logs, or repository files.

## Result

- Apple Intelligence generates an editable subject and optional body from a bounded staged diff and recent commit style.
- OpenAI, Claude, and Gemini are visible but disabled placeholders; their API-key controls do not persist input.
- Provider and staged-tree identity checks reject stale model responses.
- Generate remains actionable when Apple Intelligence is unavailable so the user receives the concrete availability error instead of a silent disabled control.
- Apple Intelligence returns a Conventional Commit type, a specific subject, and an optional non-duplicated body; formatter validation enforces the prefix and removes repeated subject text.
- The provider menu mirrors Commit Options with an explicit chevron, while Generate is an accessible icon-only overlay in the commit editor so the editor retains the full row height.
- Focused XCTest and the macOS build pass without launching the app.
