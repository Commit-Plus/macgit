# AI Commit Message Phase 2: BYOK Cloud Providers

**Branch:** `codex/byok-ai-providers`

## Tasks

- [completed] Store OpenAI, Anthropic, and Gemini API keys locally in macOS Keychain.
- [completed] Replace cloud placeholders with credential-backed provider implementations.
- [completed] Enable cloud provider selection and actionable availability feedback in the expanded commit bar.
- [completed] Replace placeholder Settings controls with save, replace, and remove flows.
- [completed] Add focused credential, request, response, and controller tests.
- [completed] Compile targeted tests, run `git diff --check`, and build the macOS app without launching it.

## Acceptance criteria

- API keys never enter UserDefaults, Firebase, logs, repository files, or generated commit context.
- Keys are stored as device-local generic-password items in macOS Keychain and can be replaced or removed.
- OpenAI, Claude, and Gemini can be selected from the existing commit-bar menu.
- Selecting an unconfigured provider remains actionable and Generate presents a concrete missing-key error.
- Cloud requests use the same bounded repository context, Conventional Commit formatter, and stale-response checks as Apple Intelligence.
- Provider HTTP failures and invalid responses are presented to the user without exposing the API key.
- No generation path stages files, commits, or uploads more source context than the selected provider budget permits.

## Non-goals

- Syncing credentials or provider choices through Firebase.
- Automatically discovering every model exposed by a provider account.
- Adding a proxy service, usage billing, streaming output, or automatic commits.

## Result

- OpenAI uses the Responses API with GPT-4o mini, no reasoning, and strict JSON schema output.
- Claude uses the Messages API with Claude Haiku 4.5 and `output_config.format` JSON schema output.
- Gemini uses `generateContent` with Gemini 3.5 Flash-Lite, minimal thinking, and structured JSON output.
- Cloud provider keys support save, replace, and remove operations through device-local Keychain items.
- The existing expanded commit-bar menu selects all four providers and shows missing-key availability inline.
- Cloud output passes through the existing bounded context, Conventional Commit formatter, and source-fingerprint validation.
- App build and test-target compilation pass. The focused test runner hit the known Firebase host-bootstrap `abort()` before establishing a test connection, so it was not re-run.
