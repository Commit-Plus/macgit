# Repository AI Phase 3: File-Aware Context and Citations

**Branch:** `codex/repository-ai-file-context-citations`

## Goal

Let Repository AI inspect an explicitly eligible repository file or file diff when broad change context is insufficient, then return citations that Commit+ validates and can navigate to the relevant file, commit, and line or diff hunk.

## Independent delivery

- This phase may start from the completed Phase 1 baseline without Phase 2, Phase 4, or Phase 5.
- Without Phase 2, file inspection is exposed through explicit changed-file selection, citation-aware quick actions, and follow-up context controls; the app invokes the typed file tool before calling the provider.
- With Phase 2 present, the same typed services register as model-callable tools. No file-reading code is duplicated in the harness.
- Phase 3 owns validated file references and source citations. It does not require branch comparison, pull-request data, or write access.

## Architecture

```text
Repository AI panel or optional agent harness
  -> RepositoryAIFileContextService
       -> validated repository-relative path and source
       -> GitStatusService diff/blob APIs or bounded untracked reader
  -> selected provider returns RepositoryAIAnswer
       -> citation validator
       -> navigable citation UI
```

## Scope decisions

- Add typed operations for listing eligible changed files, reading a bounded file diff, and reading bounded file context.
- A path becomes eligible only after Commit+ discovers it from a trusted Git status, diff, or validated commit result. The model cannot invent an arbitrary filesystem path and make it readable.
- Prefer Git object/index reads for tracked content. Read an untracked working-tree file only after containment, regular-file, symlink, size, encoding, and binary checks.
- Citations are structured data validated against the exact returned context; Markdown authored by the provider cannot manufacture a clickable local-file target.
- Keep cloud-provider source budgets and existing Repository AI access policy unchanged.

## Task 1 — File reference and answer models

- [ ] Add `RepositoryAIFileReference` with repository-relative path, source (`workingTree`, `index`, or validated commit object), optional object ID, and evidence fingerprint.
- [ ] Add `RepositoryAITextRange`, `RepositoryAIDiffRange`, and `RepositoryAICitation` with stable IDs and user-facing labels.
- [ ] Replace the repository-answer string at the new seam with `RepositoryAIAnswer(text:citations:)`; retain a compatibility initializer for Phase 1 providers while the adapters migrate.
- [ ] Add an evidence manifest that records which paths, source versions, line ranges, and diff hunks were actually exposed during the request.
- [ ] Reject duplicate, out-of-range, unknown-path, wrong-source, stale, or malformed citations before presentation.

## Task 2 — Safe file-context services

- [ ] Add `RepositoryAIFileContextServicing` independently of SwiftUI and implement it on or alongside `GitStatusService`.
- [ ] Implement `list_changed_files` from current status and validated commit-change data, preserving staged versus unstaged identity for the same path.
- [ ] Implement `read_file_diff` with typed source/base/head inputs, `--` path separation, no external diff/textconv, bounded hunk count, bounded context lines, and truncation metadata.
- [ ] Implement `read_file_context` for:
  - a tracked working-tree version;
  - an index version;
  - a file at an already validated commit object;
  - an eligible untracked regular UTF-8 file inside the repository.
- [ ] Normalize paths without resolving outside the repository. Reject absolute paths, `..`, `.git` internals, submodule traversal, symlink escapes, devices, directories, binaries, non-UTF-8 data, and oversized content.
- [ ] Return numbered lines and stable source fingerprints so citations can be verified without trusting provider output.
- [ ] Budget metadata, requested line windows, and content separately so one large file cannot consume the entire conversation.

## Task 3 — Provider response and citation validation

- [ ] Define one provider-neutral structured answer schema containing Markdown text and citation records.
- [ ] Apple Intelligence uses `@Generable`; cloud providers use their existing structured-output mechanisms where supported and validated JSON decoding otherwise.
- [ ] Include opaque evidence IDs in provider context. Providers cite evidence IDs and relative ranges, never absolute local paths.
- [ ] Validate every citation against the evidence manifest and current fingerprint before accepting the answer.
- [ ] Preserve a useful text answer when optional citations are absent, but surface invalid provider citations as non-clickable text rather than opening the wrong source.
- [ ] Keep repository content wrapped and instructed as untrusted data in every provider request.

## Task 4 — Standalone and harness integrations

- [ ] Add a changed-file context picker to Repository AI that distinguishes Working Tree, Staged, and Commit sources.
- [ ] Add Review File and Explain Selection entry points that work on the Phase 1 fixed-context controller without an agent loop.
- [ ] When Phase 2 is available, register `list_changed_files`, `read_file_diff`, and `read_file_context` through its tool registry and use the same evidence manifest for the final answer.
- [ ] If Phase 2 is absent, preserve enough typed tool metadata that later registration is an adapter-only change.
- [ ] Keep New Conversation, provider switching, feature access, cancellation, and stale-result behavior consistent with the existing panel.

## Task 5 — Citation presentation and navigation

- [ ] Render citations as compact buttons below or inline with the relevant answer section without allowing provider-authored Markdown URLs to open local files.
- [ ] A working-tree/index citation selects the matching File Status row and opens the built-in diff at the validated hunk or line when available.
- [ ] A commit citation navigates to/selects the commit in History and opens its file detail without losing the user's existing History pagination depth.
- [ ] Provide Copy Path and Copy Citation Text actions while preserving the original repository path value.
- [ ] Clearly label stale/unavailable citations and disable navigation instead of silently opening a newer source version.
- [ ] Support keyboard focus, VoiceOver labels, and non-color-only source distinctions.

## Task 6 — Tests and verification

- [ ] Model tests cover path/source identity, evidence manifests, line/diff ranges, and citation validation.
- [ ] Service tests use real temporary repositories for staged/unstaged versions of one file, renamed paths, deleted paths, untracked files, symlinks, submodules, binary data, non-UTF-8 data, large files, malicious path inputs, and stale objects.
- [ ] Provider fixture tests cover valid citations, missing citations, malformed structured output, invented evidence IDs, and unsupported structured-output behavior.
- [ ] Controller tests cover the standalone Phase 1 path and, when compiled with the Phase 2 seam, typed tool registration without duplicate execution code.
- [ ] Navigation tests cover File Status selection, History selection/pagination preservation, stale citation disabling, and copy behavior.
- [ ] Run `git diff --check`, focused Repository AI/file/citation tests, the full suite for this non-trivial change, and the macOS build sequentially without launching the app. Do not rerun the documented Firebase bootstrap abort.

## Acceptance criteria

- A user can select a staged, unstaged, untracked, or commit file and ask a follow-up grounded in bounded file content or diff context.
- No provider/model-controlled path can escape the eligible repository evidence set or read `.git`, arbitrary local files, symlink targets outside the repository, or unsupported binary content.
- Every clickable citation resolves to evidence actually supplied to the model and is disabled when that evidence is stale.
- The phase works from the Phase 1 baseline; Phase 2 integration, if available, is additive rather than required.
- Existing commit-message, conflict-resolution, provider configuration, and repository workflows remain unchanged.

## Non-goals

- Arbitrary repository search, whole-repository indexing, embeddings, RAG, or semantic code navigation.
- Branch-wide, history-wide, or pull-request analysis; those belong to Phase 4.
- File editing, patch application, staging, committing, checkout, or other mutations.
- Opening provider-authored absolute paths or unvalidated Markdown links.

## Cross-phase integration contract

Phase 3 exports typed file-context services and citation models. Phase 2 may expose the services as tools, Phase 4 may reuse citations for branch/history/PR evidence, and Phase 5 may cite proposed mutation targets. None of those integrations changes Phase 3's standalone acceptance.
