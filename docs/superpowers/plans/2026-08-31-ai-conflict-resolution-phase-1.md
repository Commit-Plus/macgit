# AI Conflict Resolution Phase 1: Autonomous Text Conflicts

**Branch:** `codex/ai-conflict-resolver`

## Tasks

- [completed] Add conflict AI snapshots, stable fingerprints, typed decisions, tolerant JSON decoding, and validation.
- [completed] Extend the provider-neutral AI seam with conflict-resolution generation.
- [completed] Add a main-actor orchestration controller that resolves files sequentially and stages complete results.
- [completed] Present grouped Needs User questions without requiring per-line approval.
- [completed] Add Resolve All with AI, provider selection, progress, cancellation, and result summaries to the resolver window.
- [completed] Add focused model, prompt, controller, and Git integration tests.
- [completed] Run `git diff --check`, compile focused tests, and build the macOS app without launching it.

## Acceptance criteria

- One action processes all supported conflicted text files.
- Every conflict section receives exactly one typed decision.
- AI can take Current, Incoming, either Both order, or replace the block with newly generated code.
- Complete valid files are written and staged automatically.
- Files containing Needs User decisions are not written or staged until those decisions are answered.
- The app rejects stale responses and keeps unsupported/binary conflicts available for manual resolution.
- The selected on-device or BYOK provider and existing access policy are reused.
- Errors are visible and the app remains usable after cancellation or partial success.

## Non-goals

- Arbitrary shell/tool execution requested by the model.
- Automatic build/test commands from repository configuration.
- Edits to non-conflicted files.
- Automatic merge commits or pushes.
- Persistent batch undo; that is Phase 3.

## Result

- The resolver window exposes one provider-aware Resolve All with AI action and blocks concurrent manual edits while a batch is running.
- Apple Intelligence uses a typed `@Generable` response. OpenAI, Claude, Gemini, and OpenRouter request JSON-schema output; DeepSeek uses JSON object mode.
- Each text-conflict file includes optional Base, Current, Incoming, bounded surrounding context, every stable section index, and a SHA-256 fingerprint.
- Complete plans are validated, written, checked with `git diff --check`, and staged automatically. Stale, binary, non-UTF-8, oversized, malformed, and incomplete files remain available for manual resolution with actionable errors.
- Needs User decisions are grouped into one sheet with directly applicable options; files with unanswered decisions are not modified.
- Focused test sources cover decoding, plan validation, automatic application, user decisions, Base loading, fingerprints, and Git staging. `build-for-testing` and the macOS app build pass. The targeted runner reached the known Firebase test-host bootstrap abort before establishing a test connection and was not re-run.
