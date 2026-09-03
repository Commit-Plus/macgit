# Repository AI Phase 2: Agentic Read-Only Git Harness

**Branch:** `codex/repository-ai-agentic-git-harness`

## Goal

Let Repository AI decide which safe Git queries it needs, execute them through Commit+'s existing Git runtime, inspect results, recover from ordinary Git command failures, and continue until it can answer the user's repository question. The first required behavior is correctly reviewing staged-only changes when the user asks for them.

## Independent delivery

- This phase may start directly from the completed Phase 1 baseline. It does not require the file tools, repository-analysis tools, citations, or mutation tools planned in Phases 3–5.
- Phase 2 owns the provider-neutral agent loop, generic read-only Git policy, and tool transport. Its acceptance is complete with only `execute_git` registered.
- If another phase has already added typed Repository AI tools, Phase 2 adapts those existing tools into its registry after the core harness works; their absence does not block this phase.
- If Phase 2 merges first, later phases register tools through its public tool protocol. If another phase merges first, Phase 2 reuses that phase's existing models/services rather than replacing them.

## Architecture

```text
RepositoryAIChatController
  -> RepositoryAIAgentHarness
       -> selected provider's tool-calling adapter
       -> RepositoryAIGitCommandExecutor
            -> RepositoryAIGitCommandPolicy
            -> GitStatusService.runGit(arguments:in:environment:)
       -> tool result returned to the provider
       -> repeat or produce the final response
```

The existing `GitStatusService.runGit` family remains the only process-execution seam. The executor uses its environment overload to add app-owned safety settings. The AI layer receives no shell string, executable path, working-directory override, or environment override; it supplies only a validated Git argument array.

## Scope decisions

- Expose one provider tool named `execute_git` with an `arguments: [String]` parameter.
- Keep Phase 2 strictly read-only. Network commands and repository mutations are rejected even if Git describes them as queries.
- Require at least one successful Git tool call before accepting a repository-grounded final answer.
- Let a normal Git failure return to the model as a tool result so it can correct a ref, option, or path and try again.
- Treat a policy rejection, timeout, cancellation, stale repository snapshot, or exhausted budget as a harness-level stop condition.
- Preserve the existing provider, API-key, model-selection, entitlement, and Repository AI panel architecture.
- Do not use arbitrary shell execution, repository-provided scripts, Git aliases, external diff drivers, textconv filters, pagers, hooks, or interactive credential prompts.

## Task 1 — Provider-neutral agent contracts

- [ ] Replace `RepositoryAIToolCall`'s two caller-selected cases with provider-neutral agent turn types:
  - tool definition and JSON schema;
  - tool invocation ID, name, and decoded arguments;
  - success, Git failure, and truncated tool results;
  - assistant text versus requested tool calls;
  - bounded conversation transcript entries.
- [ ] Add a provider capability check so an unsupported configured model fails with actionable feedback instead of silently falling back to an ungrounded response.
- [ ] Extend the provider seam with a Repository AI agent-session API while leaving commit-message and conflict-resolution generation unchanged.
- [ ] Keep provider-specific response IDs, content blocks, and continuation metadata inside provider adapters rather than leaking them into the controller or Git executor.

## Task 2 — Read-only Git policy and executor

- [ ] Add `RepositoryAIGitCommandPolicy` as a pure, exhaustively tested validator over `[String]`.
- [ ] Add `RepositoryAIGitCommandExecutor` that validates arguments and delegates accepted commands to the existing environment-aware `GitStatusService.runGit` overload.
- [ ] Start with explicit argument grammars for:
  - `status` in porcelain/read-only forms;
  - `diff` for working tree, `--cached`, refs, statistics, and bounded patches;
  - `show` for commit metadata and patches, but not arbitrary blob/file extraction;
  - `log` with bounded counts and approved formats;
  - `rev-parse` for validated commit-ish resolution and current repository state;
  - `ls-files` for index/untracked discovery;
  - `branch --show-current`, `for-each-ref`, and `merge-base` in approved query forms.
- [ ] Use positive option allow-lists per subcommand. Reject global Git options supplied by the model, including configuration, executable-path, Git-directory, and work-tree overrides.
- [ ] Reject every mutation or network-capable command, including `add`, `rm`, `restore`, `checkout`, `switch`, `reset`, `clean`, `commit`, `merge`, `rebase`, `cherry-pick`, `revert`, `stash`, `tag`, branch mutations, `config`, `fetch`, `pull`, `push`, `clone`, `ls-remote`, submodule mutations, and worktree mutations.
- [ ] Inject safe execution settings owned by the app: no pager, no terminal prompt, no color, no external diff, and no textconv.
- [ ] Bound output before it can grow without limit. Enhance the existing Git process seam with a byte ceiling if post-execution truncation cannot provide a real memory bound; do not create a second Git runtime.
- [ ] Return a compact result containing normalized command display text, success/failure, output, and truncation state. Never return credentials or inherited environment values.

## Task 3 — Agent loop, budgets, and stale-state protection

- [ ] Add `RepositoryAIAgentHarness` to coordinate provider turns and tool execution independently of SwiftUI.
- [ ] Require tool use on the first provider turn where the provider supports a required-tool mode. For providers without a reliable required mode, reject a final answer with no successful tool evidence and retry once with a grounding reminder.
- [ ] Default to at most six Git calls per user request, one active command at a time, a per-command timeout, a total request deadline, and a provider-budget-derived cumulative tool-output ceiling.
- [ ] Allow the model to continue after ordinary Git failures, but count failed calls against the same limits.
- [ ] Capture repository identity at request start and revalidate before accepting the final response. Cover at least current branch/HEAD, index identity, and working-tree fingerprint so mixed-state answers are rejected.
- [ ] Propagate cancellation from the panel through the harness to the active provider request or Git `Process`.
- [ ] Keep tool output explicitly marked as untrusted repository data in every provider prompt/transcript.
- [ ] Compact older conversation and tool entries within the selected provider's input budget; never rely on a remote session ID as the sole conversation record.

## Task 4 — Provider adapters

- [ ] Apple Intelligence: implement a Foundation Models `Tool` whose `@Generable` arguments contain `[String]`; create `LanguageModelSession` with that tool and reuse its transcript for the conversation. Route every call through the shared executor and enforce the same call/output limits inside the tool.
- [ ] OpenAI Responses API: send a strict `execute_git` function schema, decode `function_call` output, execute locally, and append `function_call_output` using the matching call ID until final text is returned.
- [ ] Anthropic Messages API: send the tool schema, decode `tool_use` blocks, and return matching `tool_result` blocks in the next user message.
- [ ] Gemini `generateContent`: send `functionDeclarations`, decode `functionCall`, and append matching `functionResponse` content while preserving the model turn history.
- [ ] DeepSeek Chat Completions: use its OpenAI-compatible function-calling request and `tool_calls`/tool-result message loop; surface a clear provider/model compatibility error if the configured model rejects tools.
- [ ] OpenRouter Chat Completions: use the standardized tool-calling messages, retain assistant tool-call messages verbatim, set `provider.require_parameters = true`, and fail actionably when the selected routed model does not support `tools`.
- [ ] Add request/response fixture tests for every provider so payload drift cannot silently disable the harness.

Provider contracts must follow their official tool-calling formats: [Apple Foundation Models](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling), [OpenAI Responses API](https://developers.openai.com/api/docs/guides/function-calling), [Anthropic Messages API](https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview), [Gemini API](https://ai.google.dev/gemini-api/docs/function-calling), [DeepSeek API](https://api-docs.deepseek.com/guides/function_calling), and [OpenRouter](https://openrouter.ai/docs/guides/features/tool-calling).

## Task 5 — Controller and panel integration

- [ ] Change free-form submission so `RepositoryAIChatController` sends the user question to the harness without preselecting `.workingTreeChanges`.
- [ ] Convert Review Changes and Explain Commit quick actions into normal grounded prompts with relevant hints, not hard-coded data extraction paths.
- [ ] Preserve local multi-turn conversation history across follow-up questions and reset it only through New Conversation or repository/window teardown.
- [ ] Show compact, non-editable activity rows such as `Read staged diff` or `Inspected HEAD`; keep raw command/output available through a disclosure view for debugging without mixing it into assistant prose.
- [ ] Keep the composer disabled during an active request, expose cancellation, and surface policy/budget/stale-state failures as actionable assistant messages.
- [ ] Ensure tool activity is accessible to VoiceOver and does not rely on color alone.

## Task 6 — Tests and verification

- [ ] Policy unit tests accept every documented safe form and reject command chaining attempts, global overrides, output-file options, aliases, external helpers, mutation commands, network commands, malformed refs, and path escapes.
- [ ] Executor tests cover safe environment injection, command logging, stdout/stderr normalization, output truncation, timeout, and cancellation.
- [ ] Harness tests cover one-call answers, multiple calls, corrected Git failures, parallel tool-call payloads serialized locally, no-tool rejection, unknown tools, malformed arguments, maximum-call exhaustion, total budget exhaustion, provider changes, and stale repository state.
- [ ] Real temporary-repository integration tests prove:
  - a repository containing only staged changes is reviewed through `diff --cached`;
  - staged and unstaged versions of the same file remain distinguishable;
  - untracked files are discoverable without arbitrary filesystem reads;
  - no accepted command changes HEAD, refs, index, working-tree bytes, remotes, or configuration.
- [ ] Controller tests prove a free-form `review staged files` prompt is not forced through the old working-tree tool and that follow-up turns retain bounded context.
- [ ] Run `git diff --check`, focused Repository AI/provider tests, and the macOS build sequentially without launching the app. Run the full suite for this non-trivial change; if it hits the documented Firebase bootstrap abort before assertions, do not rerun it.

## Acceptance criteria

- `review staged files` causes the model to obtain staged evidence, normally through `git diff --cached`, and produces an answer grounded in that result.
- The model can run several approved Git queries, observe ordinary failures, correct a query, and then answer within fixed call, time, and context budgets.
- Every provider supported by Repository AI either completes the same agent flow or reports a concrete tool-capability error.
- No model-generated input reaches a shell, chooses an executable or repository directory, changes environment policy, invokes a network operation, or mutates Git/repository state.
- Repository changes during the loop invalidate the final answer rather than mixing old and new evidence.
- Existing provider configuration, feature access, commit-message generation, conflict resolution, and manual Git workflows remain unchanged.

## Non-goals

- Staging, unstaging, committing, checking out branches, resetting, cleaning, stashing, merging, rebasing, fetching, pulling, pushing, or changing configuration.
- Arbitrary filesystem reads, source editing, patch application, build/test execution, repository scripts, hooks, MCP, or shell access.
- Automatically approving commands based only on model explanations.
- Streaming assistant prose; tool activity may update incrementally, but response streaming can remain a later refinement.

## Follow-up phase boundary

Phase 5 may introduce write operations as separate semantic tools such as `stage_files`, `create_commit`, or `checkout_branch`. Each such tool requires its own typed inputs, preview, explicit user confirmation, expected-state checks, error recovery, repository refresh, and Git Undo integration where an inverse is supported. It must not widen `execute_git` beyond read-only query forms.
